import Foundation

public enum ChildFailureResolution {
  case Resume
  case Stop
  case Restart
  case Escalate
}

public enum RestartStrategy {
  case OneForOne(resolution: ChildFailureResolution)
}

public protocol Actor: class {
  var context: ActorContext { get set }
  func receive(msg: Any) throws
  func handleFailure(child: ActorRef, error: Error) -> RestartStrategy
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

public class : Actor {
  public var context: ActorContext = NoActorContext
  
  
  public func receive(msg: Any) throws {
    throw ActorErrors.UnhandledMessage
  }
  
  public func handleFailure(child: ActorRef, error: Error) -> RestartStrategy {
    switch error {
    case ActorErrors.UnhandledMessage:
      return .OneForOne(resolution: .Resume)
    default:
      return .OneForOne(resolution: .Restart)
    }
  }
}

struct UninitializedContext: ActorContext {
  var parent: ActorRef {
    get {
      return Nobody
    }
  }
  
  var this: ActorRef {
    get {
      return Nobody
    }
  }
  
  var sender: ActorRef {
    get {
      return Nobody
    }
  }
  
  func actor(named: String,
             _ factory: @autoclosure @escaping () -> Actor) -> ActorRef? {
    return Nobody
  }
  
  func actor(factory: @escaping () -> Actor) -> ActorRef {
    return Nobody
  }
}

public let NoActorContext: ActorContext = UninitializedContext()
