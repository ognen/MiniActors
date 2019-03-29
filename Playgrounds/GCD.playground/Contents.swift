import Foundation

// Parallel

extension Sequence {
  func pmap
    <R: Sequence>
    (f: Element -> R.Element) -> R
  {
    // ...
  }
  
  func preduce<R>(init: R, f: (R, Element) -> R) -> R
  {
    // ,,,
  }
  
  func pfilter(f: Element -> Bool) -> Self {
    // ...
  }
  
  func pflatMap
    <R: Sequence>
    (f: Element -> R) -> R
  {
    // ...
  }
}


let arr: [String]

let result = arr
  .pmap({ $0.uppercased() })
  .pfilter({ $0.count > 10 })
  .preduce(init: "", { $1.count > $0.count ? $1 : $0})

func calculateSquare(of value: Double) -> Double {
  return value * value
}

func firstKeyStrokeOfUser() -> ??? {
  
}

func firstKeyStrokeOfUser(done: String -> ()) {
  // ...
}

func firstKeyStrokeOfUser() -> Promise<String> {
  
}

// Threads

@objc
class DBThread: Thread {
  var done = false
  
  override func main() {
    self.name = "Realm Access Thread"
    
    while (!self.done) {
      _ = autoreleasepool {
        RunLoop.current.run(mode: .defaultRunLoopMode, before: Date(timeIntervalSinceNow: 1))
      }
    }
  }
}

let t = DBThread()
let obj = someObj()
t.start()
obj.perform(#selector(bla:), on: t, with: nil, waitUntilDone: false)


let queue = DispatchQueue(label: "Concuyrrent", attributes: .concurrent)

queue.async {
  ;///
}

let val = queue.sync {
  // ...
  return 42
}
// GCD


class Jail {
  var prisoners: [String] = []
  
  func main() {
    DispatchQueue.global().async {
      prisoners.append("John")
    }
    
    DispatchQueue.global().async {
      prisoners.append("Doe")
    }
  }
}


class Jail2 {
  let prisoners = ["John", "Doe"]
  
  func main() {
    DispatchQueue.global().async {
      if prisoners.contains("John") {
        // ...
      }
    }
    
    DispatchQueue.global().async {
      if prisoners.contains("Doe") {
        // ...
      }
    }
  }
}

class FixedJail {
  var prisoners: [String] = []
  
  let q = DispatchQueue(label: "Jail Watch")
  
  func main() {
    q.async {
      prisoners.append("John")
    }
    
    q.async {
      prisoners.append("Doe")
    }
  }
}

class AdvancedJail {
  var prisoners: [String] = []
  
  let q = DispatchQueue(label: "Jail Watch", attributes: .concurrent)

  func main() {
    q.sync(flags: .barrier) {
      prisoners.append("John")
    }
    
    q.async {
      if prisoners.contains("John") {
        // ...
      }
    }
    
    q.async(flags: .barrier) {
      prisoners.append("Doe")
    }
  }

}

// Never do this!
class AdvancedJail {
  var prisoners: [String] = []
  
  let q = DispatchQueue(label: "Jail Watch", attributes: .concurrent)
  
  func main() {
    var johnIsThere = false
    
    q.async(flags: .barrier) {
      prisoners.append("John")
    }
    
    q.async {
      if prisoners.contains("John") {
        johnIsThere = true
      }
    }
    
    q.async(flags: .barrier) {
      if johnIsThere {
        prisoners.removeAll(where: {$0 == "John"})
      }
    }
  }
}

// DO THIS
class AdvancedJail {
  var prisoners: [String] = []
  
  let q = DispatchQueue(label: "Jail Watch", attributes: .concurrent)
  
  func main() {
    
    q.async(flags: .barrier) {
      prisoners.append("John")
    }
    
    // "transaction"
    q.async(flags: .barrier) {
      var johnIsThere = prisoners.contains("John")

      if johnIsThere {
        prisoners.removeAll(where: {$0 == "John"})
      }
    }
  }
}


// Sync

/

