import XCTest
import MiniActors

class ActorPathTests: XCTestCase {
  func testActorPaths() {
    let root = Path.root
 
    XCTAssertEqual(root.elements, [])
    XCTAssertEqual(root.parent, root)
    
    XCTAssertEqual((root / "bla").elements, ["bla"])
    XCTAssertEqual((root / "bla").parent, root)
    
    XCTAssertEqual(root / ["foo", "bar"], root / "foo" / "bar")
    XCTAssertEqual(root / "foo/bar",  root / "foo" / "bar")
    
    let path: Path = Path("/foo/bar/baz")!
    XCTAssertEqual(path.elements,  ["foo", "bar", "baz"])
    
    let path2: Path = Path("foo/bar/baz")!
    XCTAssertEqual(path, path2)
  }
  
  func testDotandDotDot() {
    let root = Path.root
    
    XCTAssertEqual(root / "foo/bar/baz" / "../x", root / "foo/bar/x")
    XCTAssertEqual(root / "foo/bar" / "./x", root / "foo/bar/x")
    XCTAssertEqual(root / "..", root)
    XCTAssertEqual(root / "bar/../../../x", root / "x")
  }
  
  func testRelativePaths() {
    let root = Path.root

    let p: RelativePath = ["foo", "bar"]
    let p2 = RelativePath(elements: ["foo", "bar"])
    
    XCTAssertEqual(p, p2)
    
    XCTAssertEqual(root / ["foo", "bar"], root / "foo" / "bar")
    XCTAssertEqual(root / p, root / ["foo", "bar"])
    XCTAssertEqual(root / p2, root / ["foo", "bar"])

    XCTAssertEqual(root / "foo/bar", root / "/foo/bar")

  }
}
