import XCTest
import MiniActors

class ActorSystemTests: XCTestCase {
  
  var system: ActorSystem! = nil
  
  override func setUp() {
    system = ActorSystem(named: "Under Test")
  }
  
  override func tearDown() {
    system.stop()

    let isStopped = NSPredicate { s, _ in
      (s as? ActorSystem)?.isStopped ?? false
    }
    wait(
      for: [
        expectation(for: isStopped, evaluatedWith: system)
      ],
      timeout: 10)
  }
  
//  func testExample() {
//    let dummy = system.actor(of: SimpleActor.self)
//    
//    dummy ! "Hello"
//    // This is an example of a functional test case.
//    // Use XCTAssert and related functions to verify your tests produce the correct results.
//  }
}

enum TestingMessages {
  case QueryLast
  case ForceFail
  case LastMessage(msg: Any)
}

//enum DummyError: Error {
//  case Forced
//}
//
//class DummyActor: SimpleActor {
//  var lastMsg: Any = "None"
//
//  public required init(using context: ActorContext, props: Props) {
//    super.init(using: context, props: props)
//  }
//
//
//  override func receive(msg: Any) throws {
//    switch msg {
//    case TestingMessages.QueryLast:
//      sender ! TestingMessages.LastMessage(msg: lastMsg)
//    case TestingMessages.ForceFail:
//      throw DummyError.Forced
//    default:
//      lastMsg = msg
//    }
//  }
//}
