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
      break // impossible

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

struct Children {
  let uid: UUID
  
  private var q: DispatchQueue
  
  private var childUidByName: [String: UUID] = [:]
  private var children: [UUID:Cell] = [:]
  
  init(uid: UUID) {
    self.uid = uid
    self.q = DispatchQueue(
      label: "childern of \(uid)",
      qos: .background,
      attributes: .concurrent)
  }
  
  mutating func registerChildCell(cell: Cell, named name: String) {
    q.sync(flags: .barrier) {
      childUidByName[name] = cell.uid
      children[cell.uid] = cell
    }
  }
  
  mutating func unregisterChildCell(identifiedBy uid: UUID) {
    q.sync(flags: .barrier) { () -> () in
      children.removeValue(forKey: uid)
    }
  }
  
  
  func childCell(named name: String) -> Cell? {
    return q.sync {
      if let uid = childUidByName[name],
         let c = children[uid] {
        return c
      }
      return nil
    }
  }
  
  func childCell(identifiedBy uid: UUID) -> Cell? {
    return q.sync {
      return children[uid]
    }
  }
  
  var isEmpty: Bool {
    get {
      return q.sync {
        return children.isEmpty
      }
    }
  }
  
  var count: Int {
    get {
      return q.sync {
        return children.count
      }
    }
  }
}

extension Children: Sequence {
  typealias Iterator = Dictionary<UUID, Cell>.Values.Iterator
  
  func makeIterator() -> Children.Iterator {
    return children.values.makeIterator()
  }
}

// TYPE Erasure (base clasS)
class Cell {
  let uid = UUID()
  let name: String

  init(name: String) {
    self.name = name
  }
  
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
  
  func childCell(named name: String) -> Cell? {
    fatalError()
  }
  
  func childCell(identifiedBy uid: UUID) -> Cell? {
    fatalError()
  }
}

class ActorCell<Actr: Actor>: Cell {
  let path: Path

  let config: ActorConfig

  let definition: ActorSpec<Actr>
  var actor: Actr?

  var state: ActorState = .Operational
  
  let q: DispatchQueue
  
  var mailbox: [(ActorRef, Any)] = []
  
  let globalLookup: ActorLookup
  var childStats: [UUID:ChildStats] = [:]
  lazy var children = Children(uid: self.uid)
  
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
       globalLookup: ActorLookup,
       definition: ActorSpec<Actr>,
       config: ActorConfig) {
    self.parent = parent
    self.path = parent.path / name

    self.globalLookup = globalLookup
    self.definition = definition
    self.config = config
    
    self.q = DispatchQueue(
      label: "Actor: \(path)",
      qos: DispatchQoS.userInitiated)

    super.init(name: name)

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
      for case let c as ActorCell in children {
        c.this ! SystemMessages.Stop
      }
      
      schedule(msg: SystemMessages.FinalizeStop,
               sender: this,
               after: config.waitForChildrenToStop)
    }
    
  }
  
  func handleStoppedChild(_ child: ActorRef) {
    // TODO, clean up childUidByName or?
    children.unregisterChildCell(identifiedBy: child.uid)
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
      self.actor = definition.actor(using: ContextReference(cell: self))
    }
    
    return self.actor!
  }
  

  override func childCell(named name: String) -> Cell? {
    return children.childCell(named: name)
  }
  
  override func childCell(identifiedBy uid: UUID) -> Cell? {
    return children.childCell(identifiedBy: uid)
  }

}

extension ActorSpec {
  func actor(using context: ActorContext) -> A {
    return type.init(using: context, props: props)
  }
}


extension ActorCell: ActorCreation {
  func actorCell
    <A: Actor>
    (definedBy def: ActorSpec<A>, named name: String) -> ActorCell<A>?
  {
    switch state {
    case .Terminating, .Stopped:
      return nil
    default:
      let cell = ActorCell<A>(name: name,
                              parent: ref,
                              globalLookup: globalLookup,
                              definition: def,
                              config: self.config)

      children.registerChildCell(cell: cell, named: name)

      return cell
    }
  }
  
  func actor
    <A: Actor>
    (definedBy def: ActorSpec<A>, named name: String) -> ActorRef
  {
    if let c = actorCell(definedBy: def, named: name) {
      return c.ref
    }
    return Nobody
  }
}

extension ActorCell: ActorLookup {
  func actor(at path: RelativePath) -> ActorRef? {
    if path.isDirectSibling {
      if let cell = children.childCell(named: path.elements[0]) {
        return cell.ref
      } else {
        return nil
      }
    } else {
      return actor(at: self.path / path)
    }
  }
  
  func actor(at path: Path) -> ActorRef? {
    return globalLookup.actor(at: path)
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
    (definedBy def: ActorSpec<Actr>, named name: String) -> ActorRef
  {
    return cell!.actor(definedBy: def, named: name)
  }
}

extension ContextReference: ActorLookup {
  func actor(at path: RelativePath) -> ActorRef? {
    return cell!.actor(at: path)
  }
  
  func actor(at path: Path) -> ActorRef? {
    return cell!.actor(at: path)
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
