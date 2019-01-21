import Foundation

infix operator !

public protocol ActorRef {
  var uid: UUID { get }
  var path: Path { get }
  func tell(msg: Any, sender: ActorRef)
  func tell(msg: Any)
  //  func ask(msg: Any, sender: ActorRef, callback: (_ response: Any) throws -> ())
}

public func !(lhs: ActorRef, rhs: Any) {
  lhs.tell(msg: rhs)
}

extension ActorRef {
  public func tell(msg: Any) {
    if let actor = DispatchQueue.getSpecific(key: currentActorKey) {
      self.tell(msg: msg, sender: actor)
    } else {
      self.tell(msg: msg, sender: Nobody)
    }
  }
}

public struct AnyActorRef: ActorRef, Hashable {
  private let ref: ActorRef
  
  public init(_ ref: ActorRef) {
    self.ref = ref
  }

  public var uid: UUID {
    get {
      return ref.uid
    }
  }
  
  public var path: Path {
    get {
      return ref.path
    }
  }
  
  public func tell(msg: Any, sender: ActorRef) {
    ref.tell(msg: msg, sender: sender)
  }

  public static func == (lhs: AnyActorRef, rhs: AnyActorRef) -> Bool {
    return lhs.uid == rhs.uid
  }
  
  public func hash(into hasher: inout Hasher) {
    ref.uid.hash(into: &hasher)
  }
}

public struct RefToNobody: ActorRef, Hashable {
  public let uid = UUID()
  public let path: Path = Path.root
  
  fileprivate  init() {
    
  }
  
  // TODO: send these to dead letters once implemented
  
  public func tell(msg: Any) {
    // NOOP
  }
  
  public func tell(msg: Any, sender: ActorRef) {
    // NOOP
  }
  
  public static func ==(lhs: RefToNobody, rhs: RefToNobody) -> Bool {
    return lhs.uid == rhs.uid
  }
  
  public func hash(into hasher: inout Hasher) {
    uid.hash(into: &hasher)
  }
}

public let Nobody = RefToNobody()

