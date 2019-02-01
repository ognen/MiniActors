import Foundation

public protocol ActorCreation {
  func actor
    <Actr: Actor>
    (of type: Actr.Type, props: Actr.Props, named: String) -> ActorRef
}

public extension ActorCreation {
  public func actor
    <Actr: Actor>
    (of type: Actr.Type, named name: String) -> ActorRef
    where Actr.Props == Void
  {
    return actor(of: type, props: (), named: name)
  }
  
  public func actor
    <Actr: Actor>
    (of type: Actr.Type, props: Actr.Props) -> ActorRef
  {
    return actor(of: type, props: props, named: String(describing: UUID()))
  }
  
  public func actor
    <Actr: Actor>
    (of type: Actr.Type) -> ActorRef
    where Actr.Props == Void
  {
    return actor(of: type, props: ())
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
