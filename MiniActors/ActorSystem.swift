import Foundation

public struct ActorConfig {
  public let waitForChildrenToStop: DispatchTimeInterval
}

public let DefaultActorConfig =
  ActorConfig(waitForChildrenToStop: DispatchTimeInterval.seconds(5))


public class ActorSystem {
  let name: String
  let root: ActorCell<RootActor>
  let guardian: ActorCell<RootActor>
  
  public init(named name: String, config: ActorConfig = DefaultActorConfig) {
    self.name = name
    root = ActorCell(name: "/",
                     parent: ActorRef(SyntheticParentRef()),
                     actor: RootActor.self,
                     props: (),
                     config: config)
    
    guardian = root.actorCell(of: RootActor.self, props: (), named: "user")!
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
    (of type: Actr.Type, props: Actr.Props, named: String) -> ActorRef
  {
    return guardian.actor(of: type, props: props, named: named)
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

