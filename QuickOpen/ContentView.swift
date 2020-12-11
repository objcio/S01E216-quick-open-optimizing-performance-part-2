import SwiftUI
import Cocoa
import OSLog

let log = OSLog(subsystem: "objc.io", category: "FuzzyMatch")

let linuxFiles = try! String(contentsOf: Bundle.main.url(forResource: "linux", withExtension: "txt")!).split(separator: "\n")

public let files = swiftFiles

public struct Matrix<A> {
    var array: [A]
    let width: Int
    private(set) var height: Int
    init(width: Int, height: Int, initialValue: A) {
        array = Array(repeating: initialValue, count: width*height)
        self.width = width
        self.height = height
    }

    private init(width: Int, height: Int, array: [A]) {
        self.width = width
        self.height = height
        self.array = array
    }

    subscript(column: Int, row: Int) -> A {
        get { array[row * width + column] }
        set { array[row * width + column] = newValue }
    }
    
    subscript(row row: Int) -> Array<A> {
        return Array(array[row * width..<(row+1)*width])
    }
    
    func map<B>(_ transform: (A) -> B) -> Matrix<B> {
        Matrix<B>(width: width, height: height, array: array.map(transform))
    }
    
    mutating func insert(row: Array<A>, at rowIdx: Int) {
        assert(row.count == width)
        assert(rowIdx <= height)
        array.insert(contentsOf: row, at: rowIdx * width)
        height += 1
    }
    
    func inserting(row: Array<A>, at rowIdx: Int) -> Matrix<A> {
        var copy = self
        copy.insert(row: row, at: rowIdx)
        return copy
    }
}


public let utf8Files = files.map { Array($0.utf8) }

extension Array where Element == [UInt8] {
    public func testFuzzyMatch(_ needle: String) -> [(string: [UInt8], score: Int)] {
        let n = Array<UInt8>(needle.utf8)
        var result: [(string: [UInt8], score: Int)] = []
        let resultQueue = DispatchQueue(label: "result")
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let chunkSize = self.count/cores
        // Note: there is a bug in this code, it's only here to match the episode's contents. Here is the fix: https://github.com/objcio/S01E216-quick-open-optimizing-performance-part-2/pull/2
        DispatchQueue.concurrentPerform(iterations: cores) { ix in
            let start = ix * chunkSize
            let end = Swift.min(start + chunkSize, endIndex)
            let chunk: [([UInt8], Int)] = self[start..<end].compactMap {
                guard let match = $0.fuzzyMatch3(n) else { return nil }
                return ($0, match.score)
            }
            resultQueue.sync {
                result.append(contentsOf: chunk)
            }
        }
        return result
    }
}

extension Array where Element: Equatable {
    public func fuzzyMatch3(_ needle: [Element]) -> (score: Int, matrix: Matrix<Int?>)? {
        guard needle.count <= count else { return nil }
        var matrix = Matrix<Int?>(width: self.count, height: needle.count, initialValue: nil)
        if needle.isEmpty { return (score: 0, matrix: matrix) }
        var prevMatchIdx:  Int = -1
        for row in 0..<needle.count {
            let needleChar = needle[row]
            var firstMatchIdx: Int? = nil
            let remainderLength = needle.count - row - 1
            for column in (prevMatchIdx+1)..<(count-remainderLength) {
                let char = self[column]
                guard needleChar == char else {
                    continue
                }
                if firstMatchIdx == nil {
                    firstMatchIdx = column
                }
                var score = 1
                if row > 0 {
                    var maxPrevious = Int.min
                    for prevColumn in prevMatchIdx..<column {
                        guard let s = matrix[prevColumn, row-1] else { continue }
                        let gapPenalty = (column-prevColumn) - 1
                        maxPrevious = Swift.max(maxPrevious, s - gapPenalty)
                    }
                    score += maxPrevious
                }
                matrix[column, row] = score
            }
            guard let firstIx = firstMatchIdx else { return nil }
            prevMatchIdx = firstIx
        }
        guard let score = matrix[row: needle.count-1].compactMap({ $0 }).max() else {
            return  nil
        }
        return (score, matrix)
    }
}

struct ContentView: View {
    @State var needle: String = ""
    
    var filtered: [(string: [UInt8], score: Int)] {
        os_signpost(.begin, log: log, name: "Search", "%@", needle)
        defer { os_signpost(.end, log: log, name: "Search", "%@", needle) }
        return utf8Files.testFuzzyMatch(needle).sorted { $0.score > $1.score }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Image(nsImage: search)
                    .padding(.leading, 10)
                TextField("", text: $needle).textFieldStyle(PlainTextFieldStyle())
                    .padding(10)
                    .font(.subheadline)
                Button(action: {
                    self.needle = ""
                }, label: {
                    Image(nsImage: close)
                        .padding()
                }).disabled(needle.isEmpty)
                .buttonStyle(BorderlessButtonStyle())
            }
            List(filtered.prefix(30), id: \.string) { result in
                self.resultCell(result)
            }
        }
    }
    
    func resultCell(_ result: (string: [UInt8], score: Int)) -> some View {
        return HStack {
            Text(String(result.score))
            Text(String(bytes: result.string, encoding: .utf8)!)
        }
    }
}

// Hack to disable the focus ring
extension NSTextField {
    open override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }
}

let close: NSImage = NSImage(named: "NSStopProgressFreestandingTemplate")!
let search: NSImage = NSImage(named: "NSTouchBarSearchTemplate")!
