import Foundation

public struct ActorPath:
  CustomStringConvertible,
  Equatable,
  Hashable
{
  /**
   * The elements of the path
   */
  public let elements: [String]

  private init(elements: [String]) {
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
  
  public var parent: ActorPath {
    get {
      if elements.count == 0 {
        return self
      }
      
      return ActorPath(elements: Array(elements.dropLast()))
    }
  }
  
  func appending(_ element: String) -> ActorPath {
    if let elements = URL(string: element)?.pathComponents {
      return self.appending(elements)
    } else {
      return self
    }
  }
  
  func appending(_ elements: [String]) -> ActorPath {
    if (elements.count == 0) {
      return self
    }
   
    return ActorPath(elements: standardized(elements: self.elements + elements))
  }
  
  func standardized(elements: [String]) -> [String] {
    var result: [String] = []
    for el in elements {
      switch el {
      case ".":
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
  
  public static let root: ActorPath = ActorPath(elements: [])
  
  public static func / (lhs: ActorPath, rhs: String) -> ActorPath {
    return lhs.appending(rhs)
  }
  
  public static func / (lhs: ActorPath, rhs: [String]) -> ActorPath {
    return lhs.appending(rhs)
  }
}
