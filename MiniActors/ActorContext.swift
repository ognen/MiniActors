import Foundation

public protocol ActorCreation {
  func actor
    <Actr: Actor>
    (definedBy def: ActorSpec<Actr>, named name: String) -> ActorRef
}

public extension ActorCreation {
  func actor
    <Actr: Actor>
    (of type: Actr.Type, props: Actr.Props, named name: String = String(describing: UUID())) -> ActorRef
  {
    return actor(definedBy: ActorSpec<Actr>(props: props), named: name)
  }

  func actor
    <Actr: Actor>
    (of type: Actr.Type, named name: String = String(describing: UUID())) -> ActorRef
    where Actr.Props == Void
  {
    return actor(of: type, props: (), named: name)
  }
}

public protocol ActorLookup {
  func actor(at path: RelativePath) -> ActorRef?
  func actor(at path: Path) -> ActorRef?
}

public protocol ChildLookup {
  func child(named: String) -> ActorRef?
}

extension ChildLookup where Self: ActorLookup {
  func child(named name: String) -> ActorRef? {
    return actor(at: [name])
  }
}

public protocol ActorContext: ActorCreation, ActorLookup, ChildLookup {
  var parent: ActorRef { get }
  var this: ActorRef { get }
  var sender: ActorRef { get }
}
