import XCTest
import MiniActors

class ActorPathTests: XCTestCase {

  func testActorPaths() {
    let root = ActorPath.root
    
    assert(root.elements == [])
    assert(root.parent == root)
    
    assert((root / "bla").elements == ["bla"])
    assert((root / "bla").parent == root)
    
    assert((root / ["foo", "bar"]) == (root / "foo" / "bar"))
    assert((root / "foo/bar") == (root / "foo" / "bar"))
    
    let path: ActorPath = ActorPath("/foo/bar/baz")!
    assert(path.elements == ["foo", "bar", "baz"])
    
    let path2: ActorPath = ActorPath("foo/bar/baz")!
    assert(path == path2)
  }
  
  func testDotandDotDot() {
    let root = ActorPath.root
    
    assert(root / "foo/bar/baz" / "../x" == root / "foo/bar/x")
    assert(root / "foo/bar" / "./x" == root / "foo/bar/x")
    assert(root / ".." == root)
    assert(root / "bar/../../../x" == root / "x")
    
  }
}
