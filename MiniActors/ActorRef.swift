import Foundation

infix operator !

public typealias ActorRefProtocol = ActorMessaging & ActorIdentification

public protocol ActorMessaging {
  func tell(msg: Any, sender: ActorRefProtocol)
  func tell(msg: Any)
  //  func ask(msg: Any, sender: ActorRef, callback: (_ response: Any) throws -> ())
}

public protocol ActorIdentification {
  var uid: UUID { get }
  var path: Path { get }
}

public func !(lhs: ActorMessaging, rhs: Any) {
  lhs.tell(msg: rhs)
}

extension ActorMessaging {
  public func tell(msg: Any) {
    if let actor = DispatchQueue.getSpecific(key: currentActorKey) {
      self.tell(msg: msg, sender: actor)
    } else {
      self.tell(msg: msg, sender: Nobody)
    }
  }
}

public struct ActorRef: ActorMessaging, ActorIdentification, Hashable {
  private let ref: ActorRefProtocol
  
  public init(_ ref: ActorRefProtocol) {
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
  
  public func tell(msg: Any, sender: ActorRefProtocol) {
    ref.tell(msg: msg, sender: sender)
  }

  public static func == (lhs: ActorRef, rhs: ActorRef) -> Bool {
    return lhs.uid == rhs.uid
  }
  
  public func hash(into hasher: inout Hasher) {
    ref.uid.hash(into: &hasher)
  }
}

public struct RefToNobody: ActorMessaging, ActorIdentification {
  public let uid = UUID()
  public let path: Path = Path.root
  
  fileprivate  init() {
    
  }
  
  // TODO: send these to dead letters once implemented
  
  public func tell(msg: Any) {
    // NOOP
  }
  
  public func tell(msg: Any, sender: ActorRefProtocol) {
    // NOOP
  }
}

public let Nobody = ActorRef(RefToNobody())

