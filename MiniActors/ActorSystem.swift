import Foundation

public struct ActorConfig {
  public let waitForChildrenToStop: DispatchTimeInterval
}

public let DefaultActorConfig =
  ActorConfig(waitForChildrenToStop: DispatchTimeInterval.seconds(5))


public class ActorSystem {
  let name: String
  let config: ActorConfig
  
  lazy var systemLookup = SystemLookup(root: self)
  lazy var root: ActorCell<RootActor> =
    ActorCell(name: "/",
              parent: ActorRef(SyntheticParentRef()),
              globalLookup: systemLookup,
              definition: ActorSpec<RootActor>(),
              config: config)
  lazy var guardian: ActorCell<RootActor> =
    root.actorCell(definedBy: ActorSpec<RootActor>(),
                   named: "user")!

  public init(named name: String, config: ActorConfig = DefaultActorConfig) {
    self.name = name
    self.config = config
  }

  public var isStopped: Bool {
    get {
      return root.isStopped
    }
  }
  
  public func stop() {
    root.this ! SystemMessages.Stop
  }
  
  public func tell(msg: Any) {
    guardian.tell(msg: msg, sender: root.this)
  }
}

public func !(lhs: ActorSystem, rhs: Any) {
  lhs.tell(msg: rhs)
}

extension ActorSystem: ActorCreation {
  public func actor
    <Actr: Actor>
    (definedBy def: ActorSpec<Actr>, named name: String) -> ActorRef
  {
    return guardian.actor(definedBy: def, named: name)
  }
}

extension ActorSystem: ActorLookup {
  public func actor(at path: RelativePath) -> ActorRef? {
    return actor(at: Path.root / path)
  }
  
  public func actor(at path: Path) -> ActorRef? {
    var current: Cell? = nil
    for el in path.elements {
      if el == "/" {
        current = root
      } else if let child = current?.childCell(named: el) {
        current = child
      } else {
        return nil
      }
    }
    
    return current?.ref
  }

}

struct SyntheticParentRef: ActorRefProtocol {
  public let uid = UUID()
  public let path: Path = Path.root
  
  fileprivate init() {
    
  }
  
  func tell(msg: Any, sender: ActorRefProtocol) {
    if case SystemMessages.Failed = msg {
      sender ! SystemMessages.Stop
    }
  }
}

class RootActor: BaseActor<Void> {
  override func receive(msg: Any)  {
    // TODO, forward to dead letters
  }
  
  override func handleFailure(ofChild: ActorRef,
                              error: Error) -> ChildFailureResolution {
    return .Escalate
  }
}

struct SystemLookup<RootLookup: ActorLookup & AnyObject>: ActorLookup {
  weak var root: RootLookup?
  
  func actor(at path: RelativePath) -> ActorRef? {
    return root?.actor(at: path)
  }
  
  func actor(at path: Path) -> ActorRef? {
    return root?.actor(at: path)
  }
}
