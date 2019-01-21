import Foundation

public protocol PathSegment: Hashable {
  init(elements: [String])
  var elements: [String] { get }
  
  func appending(_ path: RelativePath) -> Self
}

public extension PathSegment {

  public static func / (lhs: Self, rhs: String) -> Self {
    return lhs.appending(RelativePath(rhs))
  }
  
  public static func / (lhs: Self, rhs: RelativePath) -> Self {
    return lhs.appending(rhs)
  }
  
  public var parent: Self {
    get {
      if elements.count == 0 {
        return self
      }
      
      return Self(elements: Array(elements.dropLast()))
    }
  }
}

public struct Path:
  PathSegment,
  CustomStringConvertible
{
  /**
   * The elements of the path
   */
  public let elements: [String]

  public init(elements: [String]) {
    self.elements = elements
  }

  private init(url: URL) {
    var elements = url.standardized.pathComponents
    if elements.count > 0 && elements[0] == "/" {
      elements.removeFirst()
    }

    self.init(elements: elements)
  }
  
  public init?(_ string: String) {
    if let url = URL(string: string) {
      self.init(url: url)
    } else {
      return nil
    }
  }
  
  public var description: String {
    get {
      return "/\(elements.joined(separator: "/"))"
    }
  }
  
  
  public func appending(_ path: RelativePath) -> Path {
    if (path.elements.count == 0) {
      return self
    }
   
    return Path(elements: standardized(base: self.elements,
                                       appending: path.elements))
  }
  
  public static let root: Path = Path(elements: [])
  
}

public struct RelativePath: PathSegment {
  
  public let elements: [String]

  public init(elements: [String]) {
    self.elements = elements
  }
  
  public init(_ path: String) {
    if let elements = URL(string: path)?.pathComponents {
      self.init(elements: elements)
    } else {
      self.init(elements: [])
    }
  }
  
  public func appending(path: String) -> RelativePath {
    if let elements = URL(string: path)?.pathComponents {
      return self.appending(RelativePath(elements: elements))
    } else {
      return self
    }
  }
  
  public func appending(_ path: RelativePath) -> RelativePath {
    if (elements.count == 0) {
      return self
    }
    
    return RelativePath(elements: standardized(base: self.elements,
                                               appending: path.elements))
  }

}

fileprivate func standardized(base: [String], appending: [String]) -> [String] {
  var result: [String] = base
  for el in appending {
    switch el {
    case  ".", "/":
      continue
    case "..":
      if result.count > 0 {
        result.removeLast()
      }
    default:
      result.append(el)
    }
  }
  
  return result
}

extension RelativePath: ExpressibleByArrayLiteral {
  public init(arrayLiteral: String...) {
    self.init(elements: arrayLiteral)
  }
}

extension RelativePath: ExpressibleByStringLiteral {
  public init(stringLiteral path: String) {
    self.init(path)
  }
}
