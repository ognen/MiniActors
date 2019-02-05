import Foundation

let currentActorKey = DispatchSpecificKey<ActorRef>()

struct InternalRef: ActorIdentification, ActorMessaging {
  weak var cell: Cell?
  let path: Path
  let uid: UUID
 
  init(path: Path, cell: Cell) {
    self.path = path
    self.cell = cell
    self.uid = cell.uid
  }
  
  func tell(msg: Any, sender: ActorRefProtocol) {
    // TODO deadletters
    cell?.tell(msg: msg, sender: ActorRef(sender))
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

struct ChildStats {
  var restartCounter: Int = 0
  var startOfWindow: DispatchTime? = nil
  let config: RestartConfig

  init(config: RestartConfig) {
    self.config = config
  }
  
  mutating func shouldRestart() -> Bool {
    switch (startOfWindow, config.withinTimeRange) {
    case (.none, .none):
      restartCounter += 1
      
    case (.none, _):
      startOfWindow = DispatchTime.now()
      restartCounter += 1

    case (.some(_), .none):
      break // impossible, we don't touch

    case (let windowStart?, let w?):
      let now = DispatchTime.now()
      if windowStart + w < now {
        restartCounter += 1
      } else {
        restartCounter = 1
        startOfWindow = now
      }
    }
    
    return restartCounter <= config.maxNumberOfRestarts

  }
}

// TYPE Erasure (base clasS)
class Cell {
  let uid = UUID()
  
  var ref: ActorRef {
    get {
        fatalError("Must be overriden by the concrete class")
    }
  }
  
  func tell(msg: Any, sender: ActorRefProtocol) {
    fatalError("Must be overidden in the concrete class")
  }
  
  var isStopped: Bool {
    get {
      fatalError()
    }
  }
}

class ActorCell<Actr: Actor>: Cell {
  let name: String
  let path: Path

  let config: ActorConfig

  let actorClass: Actr.Type
  var actor: Actr?
  let props: Actr.Props
  
  var state: ActorState = .Operational
  
  let q: DispatchQueue
  
  var mailbox: [(ActorRef, Any)] = []
  
  var childUidByName: [String: UUID] = [:]
  var children: [UUID:Cell] = [:]
  var childStats: [UUID:ChildStats] = [:]
  
  var stopped: [String] = []

  lazy var _ref = ActorRef(InternalRef(path: path, cell: self))
  
  override var ref: ActorRef {
    get {
      return _ref
    }
  }
  
  var parent: ActorRef
  var sender: ActorRef = Nobody

  init(name: String,
       parent: ActorRef,
       actor: Actr.Type,
       props: Actr.Props,
       config: ActorConfig) {
    self.name = name
    self.parent = parent
    self.path = parent.path / name
    
    self.actorClass = actor
    self.props = props
    self.config = config
    
    self.q = DispatchQueue(
      label: "Actor: \(path)",
      qos: DispatchQoS.userInitiated)

    super.init()

    self.q.setSpecific(key: currentActorKey, value: ref)
  }
  
  override var isStopped: Bool {
    get {
      return q.sync { [weak self] in
        switch self?.state {
        case .some(.Stopped):
          return true
        case .none: // reference gone by the time this runs => stopped
          return true
        default:
          return false
        }
      }
    }
  }
    
  override func tell(msg: Any, sender: ActorRefProtocol) {
    self.q.async { [weak self] in
      self?.internalTell(msg: msg, sender: sender)
    }
  }
  
  func schedule(msg: Any, sender: ActorRef, after: DispatchTimeInterval) {
    self.q.asyncAfter(deadline: DispatchTime.now() + after) { [weak self] in
      self?.internalTell(msg: msg, sender: sender)
    }
  }
  
  func internalTell(msg: Any, sender: ActorRefProtocol) {
    self.sender = ActorRef(sender)

    if case let msg as SystemMessages = msg {
      handleSystemMessage(msg: msg)
    } else {
      handleMessage(msg: msg)
    }
  }
  
  func handleSystemMessage(msg: SystemMessages) {
    switch msg {
    case .Stopped: handleStoppedChild(sender)
    case .FinalizeStop: handleFinalizeStop()
    case .Stop: doStop()
    case .Resume: doResume()
    case .Restart: doRestart()
    case .Failed(let error): handleFailedChild(sender, error: error)
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
    mailbox.append((sender, msg))
  }
  
  func deliverQueuedMessages() {
    while state == .Operational && mailbox.count > 0 {
      let (sender, msg) = mailbox.removeFirst()
      self.sender = sender
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
    parent ! SystemMessages.Failed(error: error)
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
    
    if children.isEmpty {
      self.state = .Stopped
      parent ! SystemMessages.Stopped
    } else {
      for case let c as ActorCell in children.values {
        c.this ! SystemMessages.Stop
      }
      
      schedule(msg: SystemMessages.FinalizeStop,
               sender: this,
               after: config.waitForChildrenToStop)
    }
    
  }
  
  func handleStoppedChild(_ child: ActorRef) {
    // TODO, clean up childUidByName or?
    children.removeValue(forKey: child.uid)
    childStats.removeValue(forKey: child.uid)
    
    if state == .Terminating {
      stopped.append(String(describing: child.path))
      if stopped.count == children.count {
        state = .Stopped
        parent ! SystemMessages.Stopped
      }
    }
  }
  
  func handleFinalizeStop() {
    if state != .Stopped {
      // TODO log
      state = .Stopped
      parent ! SystemMessages.Stopped
    }
    
  }
  
  func handleFailedChild(_ child: ActorRef, error: Error) {
    let actor = ensureActor()
    
    switch state {
    case .Operational, .Suspended:
      let decision = actor.handleFailure(ofChild: child, error: error)
      
      switch decision {
      case .Stop:
        child ! SystemMessages.Stop
      case .Restart:
        restart(child: child, error: error)
      case .Escalate:
        handleFailure(error)
      case .Resume:
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
      let cfg: RestartConfig
      if case .OneForOne(let config) = ensureActor().supervisorStrategy() {
        cfg = config
      } else {
        cfg = DefaultRestartConfig
      }
      
      stats = ChildStats(config: cfg)
    }
    
    if stats.shouldRestart() {
      child ! restart
    } else {
      handleFailure(error)
    }
    
    childStats[childUid] = stats
  }
  
  func ensureActor() -> Actr {
    if self.actor == nil {
      let context = ContextReference(cell: self)
      self.actor = self.actorClass.init(using: context, props: self.props)
    }
    
    return self.actor!
  }
  
}

extension ActorCell: ActorCreation {
  func actorCell
    <A: Actor>
    (of type: A.Type, props: A.Props, named name: String) -> ActorCell<A>?
  {
    return q.sync {
      switch state {
      case .Terminating, .Stopped:
        return nil
      default:
        let cell = ActorCell<A>(name: name,
                                parent: ref,
                                actor: type,
                                props: props,
                                config: self.config)
        childUidByName[name] = cell.uid
        children[cell.uid] = cell
        
        return cell
      }
    }
  }
  
  func actor
    <A: Actor>
    (of type: A.Type, props: A.Props, named name: String) -> ActorRef
  {
    if let c =  actorCell(of: type, props: props, named: name) {
      return c.ref
    }
    return Nobody
  }
}

extension ActorCell: ActorContext {
  public var this: ActorRef {
    return ref
  }
}

// use a separate struct to avoid circular references that would
// be too easily made
struct ContextReference<A: Actor, C: ActorCell<A>> {
  weak var cell: C?
  // TODO: dead letters
}

extension ContextReference: ActorCreation {
  func actor
    <Actr: Actor>
    (of type: Actr.Type, props: Actr.Props, named: String) -> ActorRef
  {
    return cell!.actor(of: type, props: props, named: named)
  }
}

extension ContextReference: ActorContext {
  // The context shoud
  public var sender: ActorRef {
    return cell!.sender
  }
  
  public var parent: ActorRef {
    return cell!.parent
  }
  
  public var this: ActorRef {
    return cell!.this
  }
}
