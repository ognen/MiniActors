import Foundation

public protocol ActorCreation {
  func actor(named: String, _ factory: @autoclosure @escaping () -> Actor) -> ActorRef?
}

public extension ActorCreation {
  public func actor(factory: @autoclosure @escaping () -> Actor) ->ActorRef {
    return actor(named: String(describing: UUID()),  factory)!
  }
}

public protocol ActorLookup {
  func selectActor(_ path: RelativePath) -> ActorRef?
  func selectActor(_ path: Path) -> ActorRef?
}

public extension ActorLookup {
  func selectActor(_ name: String) -> ActorRef? {
    return selectActor([name])
  }
}

public protocol ChildLookup {
  func child(named: String) -> ActorRef?
}


public protocol ActorContext: ActorCreation {
  var parent: ActorRef { get }
  var this: ActorRef { get }
  var sender: ActorRef { get }
}
