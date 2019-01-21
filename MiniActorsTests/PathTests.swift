import XCTest
import MiniActors

class ActorPathTests: XCTestCase {

  func testActorPaths() {
    let root = Path.root
    
    assert(root.elements == [])
    assert(root.parent == root)
    
    assert((root / "bla").elements == ["bla"])
    assert((root / "bla").parent == root)
    
    assert((root / ["foo", "bar"]) == (root / "foo" / "bar"))
    assert((root / "foo/bar") == (root / "foo" / "bar"))
    
    let path: Path = Path("/foo/bar/baz")!
    assert(path.elements == ["foo", "bar", "baz"])
    
    let path2: Path = Path("foo/bar/baz")!
    assert(path == path2)
  }
  
  func testDotandDotDot() {
    let root = Path.root
    
    assert(root / "foo/bar/baz" / "../x" == root / "foo/bar/x")
    assert(root / "foo/bar" / "./x" == root / "foo/bar/x")
    assert(root / ".." == root)
    assert(root / "bar/../../../x" == root / "x")
  }
  
  func testRelativePaths() {
    let root = Path.root

    let p: RelativePath = ["foo", "bar"]
    let p2 = RelativePath(elements: ["foo", "bar"])
    
    assert(p == p2)
    
    assert((root / ["foo", "bar"]) == (root / "foo" / "bar"))
    assert((root / p) == (root / ["foo", "bar"]))
    assert((root / p2) == (root / ["foo", "bar"]))

    assert((root / "foo/bar") == (root / "/foo/bar"))

  }
}
