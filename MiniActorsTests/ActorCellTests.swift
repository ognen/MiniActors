import XCTest
@testable import MiniActors

let Fail = UUID()
enum LoopbackErrors: Error {
  case InstructedToFail
}

struct Recv<T: Equatable>: Equatable {
  let msg: T
  let counter: Int
}

public class LoopbackActor: SimpleActor {
  var counter: Int = 0 // some state
  
  public override func receive(msg: Any) throws {
    switch msg {
    case Fail as UUID:
      throw LoopbackErrors.InstructedToFail
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

func loopbackCell() -> Cell {
  return ActorCell(name: "loopback",
                   parent: Nobody,
                   actor: LoopbackActor.self,
                   props: (),
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
    ref.tell(msg: Fail, sender: insp)
    ref.tell(msg: "H2", sender: insp)
    
    let expectations: [XCTestExpectation] = [
      expect(ref: insp, toHaveReceived: (msg: Recv(msg: "Hello", counter: 1), sender: ref)),
      expect(ref: insp, notToHaveReceived: (msg: Recv(msg: "H2", counter: 2), sender: ref))
    ]
    
    wait(for: expectations, timeout: 1)
  }
  
}
