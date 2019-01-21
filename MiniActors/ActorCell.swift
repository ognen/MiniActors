import Foundation

let currentActorKey = DispatchSpecificKey<ActorRef>()

struct InternalRef: Hashable, Equatable, ActorRef {
  weak var cell: ActorCell?
  let path: Path
  let uid: UUID
 
  init(path: Path, cell: ActorCell) {
    self.path = path
    self.cell = cell
    self.uid = cell.uid
  }
  
  
  func tell(msg: Any, sender: ActorRef) {
    cell?.tell(msg: msg, sender: sender)
  }
  
  static func == (lhs: InternalRef, rhs: InternalRef) -> Bool {
    return lhs.uid == rhs.uid
  }
  
  func hash(into hasher: inout Hasher) {
    uid.hash(into: &hasher)
  }
}

enum ActorState {
  case Operational
  case Suspended
  case Terminating
  case Stopped
}

enum SystemMessages {
  case Stop
  case FinalizeStop
  case Resume
  case Restart
  case Failed(error: Error)
  case Stopped
}

struct CellConfig {
  let maxRestarts: Int
  let waitForChildrenToStop: DispatchTimeInterval
}

struct ChildStats {
  var restartCounter: Int = 0
  
  mutating func restarted() {
    restartCounter += 1
  }
}

class ActorCell {
  let uid: UUID = UUID()
  let name: String
  let path: Path
  let creator: () -> Actor
  let config: CellConfig

  var actor: Actor?
  var state: ActorState = .Operational
  let q: DispatchQueue
  var mailbox: [(ActorRef, Any)] = []
  
  var children: [String:ActorCell] = [:]
  var childStats: [UUID:ChildStats] = [:]
  
  var stopped: [String] = []

  lazy var _this: InternalRef = InternalRef(path: path, cell: self)
  
  let _parent: InternalRef

  var _sender: ActorRef = Nobody

  init(name: String,
       parent: InternalRef,
       path: Path,
       creator: @escaping () -> Actor,
       config: CellConfig = CellConfig(maxRestarts: 10,
                                       waitForChildrenToStop:
                                        DispatchTimeInterval.seconds(10))) {
    self.name = name
    self._parent = parent
    self.path = path
    self.creator = creator
    self.config = config
    
    self.q = DispatchQueue(
      label: "Actor: \(path)",
      qos: DispatchQoS.userInitiated)
    
    self.q.setSpecific(key: currentActorKey, value: _this)
  }
  
  func tell(msg: Any, sender: ActorRef) {
    self.q.async { [weak self] in
      self?.internalTell(msg: msg, sender: sender)
    }
  }
  
  func schedule(msg: Any, sender: ActorRef, after: DispatchTimeInterval) {
    self.q.asyncAfter(deadline: DispatchTime.now() + after) { [weak self] in
      self?.internalTell(msg: msg, sender: sender)
    }
  }
  
  func internalTell(msg: Any, sender: ActorRef) {
    self._sender = sender

    if let msg = msg as? SystemMessages {
      handleSystemMessage(msg: msg)
    } else {
      handleMessage(msg: msg)
    }
  }
  
  func handleSystemMessage(msg: SystemMessages) {
    switch msg {
    case .Stopped: handleStoppedChild(_sender)
    case .FinalizeStop: handleFinalizeStop()
    case .Stop: doStop()
    case .Resume: doResume()
    case .Restart: doRestart()
    case .Failed(let error): handleFailedChild(_sender, error: error)
    }
  }
  
  func handleMessage(msg: Any) {
    switch self.state {
    case .Operational:
      doReceive(msg)
    case .Suspended:
      doQueue(msg)
    case .Terminating, .Stopped: break
      // TODO, dead letters
    }
  }
  
  func doQueue(_ msg: Any) {
    mailbox.append((_sender, msg))
  }
  
  func deliverQueuedMessages() {
    while state == .Operational && mailbox.count > 0 {
      let (sender, msg) = mailbox.removeFirst()
      self._sender = sender
      handleMessage(msg: msg)
    }
  }
  
  func doReceive(_ msg: Any) {
    let actor = ensureActor()
    
    do {
      try actor.receive(msg: msg)
    } catch  {
      handleFailure(error)
    }
  }
  
  func handleFailure(_ error: Error) {
    self.state = .Suspended
    _parent ! SystemMessages.Failed(error: error)
  }
  
  func doResume() {
    self.state = .Operational
    deliverQueuedMessages()
  }
  
  func doRestart() {
    self.state = .Operational
    self.actor = nil
    
    deliverQueuedMessages()
  }
  
  func doStop() {
    self.state = .Terminating
    self.stopped = []
    for c in children.values {
      c.this ! SystemMessages.Stop
    }
    
    schedule(msg: SystemMessages.FinalizeStop,
             sender: this,
             after: config.waitForChildrenToStop)
    
  }
  
  func handleStoppedChild(_ child: ActorRef) {
    // wrong, but since we are only doing counting
    stopped.append(String(describing: child.path))
    
    if stopped.count == children.count {
      state = .Stopped
      _parent ! SystemMessages.Stopped
    }
  }
  
  func handleFinalizeStop() {
    if state != .Stopped {
      // TODO log
    }
    
    state = .Stopped
    _parent ! SystemMessages.Stopped
  }
  
  func handleFailedChild(_ child: ActorRef, error: Error) {
    let actor = ensureActor()
    
    switch state {
    case .Operational, .Suspended:
      let decision = actor.handleFailure(child: child, error: error)
      
      switch decision {
      case .OneForOne(.Stop):
        child ! SystemMessages.Stop
      case .OneForOne(.Restart):
        restart(child: child, error: error)
      case .OneForOne(.Escalate):
        handleFailure(error)
      case .OneForOne(.Resume):
        child ! SystemMessages.Resume
      }
      
    default: break
      // do nothing
    }
  }
  
  func restart(child: ActorRef, error: Error) {
    let childUid = child.uid
    var stats: ChildStats
    if let cs = childStats[childUid] {
      stats = cs
    } else {
      stats = ChildStats(restartCounter: 0)
    }
    
    stats.restarted()
    
    // simple strategy
    if stats.restartCounter > config.maxRestarts {
      // child keeps failing, escalate
      handleFailure(error)
    } else {
      child ! restart
    }
    
    childStats[childUid] = stats
  }
  
  func ensureActor() -> Actor {
    if self.actor == nil {
      self.actor = creator()
      self.actor!.context = ContextReference(cell: self)
    }
    
    return self.actor!
  }
}

extension ActorCell: ActorCreation {
  func actor(named name: String,
             _ factory: @autoclosure @escaping () -> Actor) -> ActorRef? {
    var ref: ActorRef? = nil
    q.sync {
      if state == .Terminating {
        ref = Nobody
      } else if children[name] == nil {
        let cell = ActorCell(name: name,
                             parent: _this,
                             path: path / name,
                             creator: factory,
                             config: self.config)
        children[name] = cell
        ref = cell.this
      } else {
        // TODO Log Warning
      }
    }
    
    return ref
  }
}

extension ActorCell: ActorContext {
  public var sender: ActorRef {
    return _sender
  }
  
  public var parent: ActorRef {
    return _parent
  }
  
  public var this: ActorRef {
    return _this
  }
}

// use a separate struct to avoid circular references that would
// be too easily made
struct ContextReference {
  weak var cell: ActorCell?
  // TODO: dead letters
}

extension ContextReference: ActorCreation {
  func actor(named name: String,
             _ factory: @autoclosure @escaping () -> Actor) -> ActorRef? {
    return cell!.actor(named: name, factory)
  }
}

extension ContextReference: ActorContext {
  // The context shoud
  public var sender: ActorRef {
    return cell!._sender
  }
  
  public var parent: ActorRef {
    return cell!._parent
  }
  
  public var this: ActorRef {
    return cell!._this
  }
}
