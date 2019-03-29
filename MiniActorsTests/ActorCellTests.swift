import XCTest
import Foundation
@testable import MiniActors

let RequestToFail = UUID()
enum TestErrors: Error {
  case InstructedToFail
}

struct Recv<T: Equatable>: Equatable {
  let msg: T
  let counter: Int
}

class LoopbackActor: SimpleActor {
  var counter: Int = 0 // some state
  
 override func receive(msg: Any) throws {
    switch msg {
    case RequestToFail as UUID:
      throw TestErrors.InstructedToFail
    case let msg as String:
      counter += 1
      sender ! Recv(msg: msg, counter: counter)
    default:
      break
    }
  }
}

class InspectableRef: ActorRefProtocol {
  let uid: UUID = UUID()
  let q = DispatchQueue(label: "InspectableRef")
  var path: Path = Path.root
  
  private var _messages: [(msg: Any, sender: ActorRef)] = []
  
  func tell(msg: Any, sender: ActorRefProtocol) {
    q.async { [weak self] in
      self?._messages.append((msg: msg, sender: ActorRef(sender)))
    }
  }
  
  func clear() {
    q.async { [weak self] in
      self?._messages.removeAll()
    }
  }
  
  var messages: [(msg: Any, sender: ActorRef)] {
    get {
      return q.sync {
        return self._messages
      }
    }
  }
  
  var lastMessage: (msg: Any, sender: ActorRef)? {
    get {
      return messages.last
    }
  }
  
  var testMessages: [String] {
    get {
      var result: [String] = []
      for case let (msg as String, _) in self.messages{
        result.append(msg)
      }
      return result
    }
  }
}

struct NoLookup: ActorLookup {
  func actor(at path: Path) -> ActorRef? {
    return nil
  }
  
  func actor(at path: RelativePath) -> ActorRef? {
    return nil
  }
}

func loopbackCell() -> ActorCell<LoopbackActor> {
  return ActorCell(name: "loopback",
                   parent: Nobody,
                   globalLookup: NoLookup(),
                   definition: ActorSpec<LoopbackActor>(),
                   config: DefaultActorConfig)
}

class CellTestCase: XCTestCase {
  func expect<T: Equatable>(ref: InspectableRef,
                            toHaveReceived envelope: (msg: T, sender: ActorRef)) -> XCTestExpectation {
    let predicate = NSPredicate { (r, _) in
      guard let x = r,
            let ref = x as? InspectableRef
        else { fatalError() }
      
      for case (let msg as T, let sender) in ref.messages {
        if msg == envelope.msg && sender == envelope.sender {
          return true
        }
      }
      return false
    }
    
    return expectation(for: predicate, evaluatedWith: ref)
  }
  
  func expect<T: Equatable>(ref: InspectableRef,
                            notToHaveReceived envelope: (msg: T, sender: ActorRef)) -> XCTestExpectation {
    let predicate = NSPredicate { (r, _) in
      guard let x = r,
        let ref = x as? InspectableRef
        else { fatalError() }
      
      for case (let msg as T, let sender) in ref.messages {
        if msg == envelope.msg && sender == envelope.sender {
          return false
        }
      }
      return true
    }
    
    return expectation(for: predicate, evaluatedWith: ref)
  }
}

class SystemMessagesTests: CellTestCase {
  func testSuspend() {
    let cell = loopbackCell()
    let ref = cell.ref
    
    let insp = InspectableRef()
    
    ref.tell(msg: "Hello", sender: insp)
    ref.tell(msg: RequestToFail, sender: insp)
    ref.tell(msg: "H2", sender: insp)
    
    let expectations: [XCTestExpectation] = [
      expect(ref: insp, toHaveReceived: (msg: Recv(msg: "Hello", counter: 1), sender: ref)),
      expect(ref: insp, notToHaveReceived: (msg: Recv(msg: "H2", counter: 2), sender: ref))
    ]
    
    wait(for: expectations, timeout: 1)
  }
  
  func testResume() {
    let cell = loopbackCell()
    let ref = cell.ref
    let insp = InspectableRef()
    
    ref.tell(msg: "Hello", sender: insp)
    ref.tell(msg: RequestToFail, sender: insp)
    ref.tell(msg: "H2", sender: insp)
    ref.tell(msg: SystemMessages.Resume, sender: insp)
    ref.tell(msg: "H3", sender: insp)
    
    let expectations: [XCTestExpectation] = [
      expect(ref: insp, toHaveReceived: (msg: Recv(msg: "Hello", counter: 1), sender: ref)),
      expect(ref: insp, toHaveReceived: (msg: Recv(msg: "H2", counter: 2), sender: ref)),
      expect(ref: insp, toHaveReceived: (msg: Recv(msg: "H3", counter: 3), sender: ref))
    ]
    
    wait(for: expectations, timeout: 1)
  }
  
  func testRestart() {
    let cell = loopbackCell()
    let ref = cell.ref
    let insp = InspectableRef()
    
    ref.tell(msg: "Hello", sender: insp)
    ref.tell(msg: RequestToFail, sender: insp)
    ref.tell(msg: "H2", sender: insp)
    ref.tell(msg: SystemMessages.Restart, sender: insp)
    ref.tell(msg: "H3", sender: insp)
    
    let expectations: [XCTestExpectation] = [
      expect(ref: insp, toHaveReceived: (msg: Recv(msg: "Hello", counter: 1), sender: ref)),
      expect(ref: insp, toHaveReceived: (msg: Recv(msg: "H2", counter: 1), sender: ref)),
      expect(ref: insp, toHaveReceived: (msg: Recv(msg: "H3", counter: 2), sender: ref))
    ]
    
    wait(for: expectations, timeout: 1)
  }

  
  func testStop() {
    let cell = loopbackCell()
    let ref = cell.ref
    let insp = InspectableRef()
    
    ref.tell(msg: "Hello", sender: insp)
    ref.tell(msg: SystemMessages.Stop, sender: insp)
    ref.tell(msg: "H2", sender: insp)
    ref.tell(msg: "H3", sender: insp)
    
    Thread.sleep(forTimeInterval: 0.3)
    
    XCTAssertTrue(cell.isStopped)
    
    let expectations: [XCTestExpectation] = [
      expect(ref: insp, toHaveReceived: (msg: Recv(msg: "Hello", counter: 1), sender: ref)),
      expect(ref: insp, notToHaveReceived: (msg: Recv(msg: "H2", counter: 2), sender: ref)),
      expect(ref: insp, notToHaveReceived: (msg: Recv(msg: "H3", counter: 3), sender: ref))
    ]
    
    wait(for: expectations, timeout: 1)
  }
}

class SupervisingTests: CellTestCase {
  func testFailingChildRestart() {
    let cell = loopbackCell()
    let child = cell.actor(of: LoopbackActor.self)
    let insp = InspectableRef()
    
    child.tell(msg: "h1", sender: insp)
    child.tell(msg: RequestToFail, sender: insp)
    child.tell(msg: "h2", sender: insp)
    
    let expectations: [XCTestExpectation] = [
      expect(ref: insp, toHaveReceived: (msg: Recv(msg: "h1", counter: 1), sender: child)),
      expect(ref: insp, toHaveReceived: (msg: Recv(msg: "h1", counter: 1), sender: child)),
    ]
    
    wait(for: expectations, timeout: 1)

  }
  
  func testFailingChildTooManyRestarts() {
    let messages = [
    []]
    
    
  }
  
  func testEscalate() {
    
  }
  
  func testFailingChildStop() {
    
  }
}

