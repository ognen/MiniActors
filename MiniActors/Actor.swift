import Foundation

public enum ChildFailureResolution {
  case Resume
  case Stop
  case Restart
  case Escalate
}

public struct RestartConfig {
  let maxNumberOfRestarts: Int
  let withinTimeRange: DispatchTimeInterval?
}

public let DefaultRestartConfig =
  RestartConfig(maxNumberOfRestarts: 10,
  withinTimeRange: DispatchTimeInterval.seconds(1))

public enum RestartStrategy {
  case OneForOne(config: RestartConfig)
}

public let PoisonPill: Any = SystemMessages.Stop

public struct ActorDef<A: Actor> {
  let actor: A.Type = A.self
  let props: A.Props
}

extension ActorDef where A.Props == Void {
  init() {
    self.init(props: ())
  }
}

public protocol Actor: class {
  associatedtype Props
  
  init(using context: ActorContext, props: Props)

  var context: ActorContext { get }
  var sender: ActorRef { get }
  
  func receive(msg: Any) throws
  
  func supervisorStrategy() -> RestartStrategy
  func handleFailure(ofChild: ActorRef, error: Error) -> ChildFailureResolution
}

public extension Actor {
  public var sender: ActorRef {
    get {
      return context.sender
    }
  }
}


public enum ActorErrors: Error {
  case UnhandledMessage
}

open class BaseActor<Props>: Actor {
  
  public private(set) var context: ActorContext
  public private(set) var props: Props
  
  public required init(using context: ActorContext, props: Props) {
    self.context = context
    self.props = props
  }
  
  open func receive(msg: Any) throws {
    throw ActorErrors.UnhandledMessage
  }
  
  open func supervisorStrategy() -> RestartStrategy {
    return .OneForOne(config: DefaultRestartConfig)
  }
  
  open func handleFailure(ofChild: ActorRef, error: Error) -> ChildFailureResolution {
    switch error {
    case ActorErrors.UnhandledMessage:
      return .Resume
    default:
      return .Restart
    }
  }
}

public typealias SimpleActor = BaseActor<Void>
