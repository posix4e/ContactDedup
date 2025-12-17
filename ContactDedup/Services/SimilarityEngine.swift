import Foundation
import NaturalLanguage
import CoreML

class SimilarityEngine {
    static let shared = SimilarityEngine()

    private let embedding: NLEmbedding?

    private init() {
        // Use Apple's built-in word embeddings for semantic similarity
        embedding = NLEmbedding.wordEmbedding(for: .english)
    }

    // MARK: - String Similarity Algorithms

    /// Levenshtein distance based similarity (0.0 to 1.0)
    func levenshteinSimilarity(_ s1: String, _ s2: String) -> Double {
        let str1 = s1.lowercased()
        let str2 = s2.lowercased()

        if str1 == str2 { return 1.0 }
        if str1.isEmpty || str2.isEmpty { return 0.0 }

        let distance = levenshteinDistance(str1, str2)
        let maxLen = max(str1.count, str2.count)

        return 1.0 - (Double(distance) / Double(maxLen))
    }

    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let n = a.count
        let m = b.count

        if n == 0 { return m }
        if m == 0 { return n }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)

        for i in 0...n { matrix[i][0] = i }
        for j in 0...m { matrix[0][j] = j }

        for i in 1...n {
            for j in 1...m {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }

        return matrix[n][m]
    }

    /// Jaro-Winkler similarity (0.0 to 1.0) - good for names
    func jaroWinklerSimilarity(_ s1: String, _ s2: String) -> Double {
        let str1 = s1.lowercased()
        let str2 = s2.lowercased()

        if str1 == str2 { return 1.0 }
        if str1.isEmpty || str2.isEmpty { return 0.0 }

        let jaroSim = jaroSimilarity(str1, str2)

        // Calculate common prefix (up to 4 chars)
        var prefixLen = 0
        let minLen = min(str1.count, str2.count, 4)
        let chars1 = Array(str1)
        let chars2 = Array(str2)

        for i in 0..<minLen {
            if chars1[i] == chars2[i] {
                prefixLen += 1
            } else {
                break
            }
        }

        // Winkler modification
        let scalingFactor = 0.1
        return jaroSim + (Double(prefixLen) * scalingFactor * (1.0 - jaroSim))
    }

    private func jaroSimilarity(_ s1: String, _ s2: String) -> Double {
        let chars1 = Array(s1)
        let chars2 = Array(s2)
        let len1 = chars1.count
        let len2 = chars2.count

        if len1 == 0 && len2 == 0 { return 1.0 }
        if len1 == 0 || len2 == 0 { return 0.0 }

        let matchDistance = max(0, max(len1, len2) / 2 - 1)
        var matches1 = [Bool](repeating: false, count: len1)
        var matches2 = [Bool](repeating: false, count: len2)

        var matches = 0
        var transpositions = 0

        for i in 0..<len1 {
            let start = max(0, i - matchDistance)
            let end = min(i + matchDistance + 1, len2)

            guard start < end else { continue }

            for j in start..<end {
                if matches2[j] || chars1[i] != chars2[j] { continue }
                matches1[i] = true
                matches2[j] = true
                matches += 1
                break
            }
        }

        if matches == 0 { return 0.0 }

        var k = 0
        for i in 0..<len1 {
            if !matches1[i] { continue }
            while !matches2[k] { k += 1 }
            if chars1[i] != chars2[k] { transpositions += 1 }
            k += 1
        }

        let m = Double(matches)
        return (m / Double(len1) + m / Double(len2) + (m - Double(transpositions) / 2) / m) / 3.0
    }

    /// Phonetic similarity using Soundex
    func soundexSimilarity(_ s1: String, _ s2: String) -> Double {
        let code1 = soundex(s1)
        let code2 = soundex(s2)
        return code1 == code2 ? 1.0 : 0.0
    }

    private func soundex(_ str: String) -> String {
        let input = str.uppercased().filter { $0.isLetter }
        guard let first = input.first else { return "" }

        let codes: [Character: Character] = [
            "B": "1", "F": "1", "P": "1", "V": "1",
            "C": "2", "G": "2", "J": "2", "K": "2", "Q": "2", "S": "2", "X": "2", "Z": "2",
            "D": "3", "T": "3",
            "L": "4",
            "M": "5", "N": "5",
            "R": "6"
        ]

        var result = String(first)
        var lastCode: Character? = codes[first]

        for char in input.dropFirst() {
            if let code = codes[char], code != lastCode {
                result.append(code)
                lastCode = code
            } else if codes[char] == nil {
                lastCode = nil
            }
            if result.count == 4 { break }
        }

        return result.padding(toLength: 4, withPad: "0", startingAt: 0)
    }

    /// Double Metaphone for better phonetic matching
    func metaphoneSimilarity(_ s1: String, _ s2: String) -> Double {
        let m1 = doubleMetaphone(s1)
        let m2 = doubleMetaphone(s2)

        if m1.primary == m2.primary { return 1.0 }
        if m1.primary == m2.secondary || m1.secondary == m2.primary { return 0.9 }
        if m1.secondary == m2.secondary && !m1.secondary.isEmpty { return 0.8 }

        return 0.0
    }

    private func doubleMetaphone(_ str: String) -> (primary: String, secondary: String) {
        // Simplified implementation - for full implementation consider a library
        let soundexCode = soundex(str)
        return (soundexCode, soundexCode)
    }

    // MARK: - Semantic Similarity using NLEmbedding

    func semanticSimilarity(_ s1: String, _ s2: String) -> Double {
        guard let embedding = embedding else { return 0.0 }

        let words1 = s1.lowercased().split(separator: " ").map(String.init)
        let words2 = s2.lowercased().split(separator: " ").map(String.init)

        if words1.isEmpty || words2.isEmpty { return 0.0 }

        var totalSim = 0.0
        var count = 0

        for w1 in words1 {
            for w2 in words2 {
                let distance = embedding.distance(between: w1, and: w2)
                // Convert distance to similarity (distance is 0-2, we want 0-1 similarity)
                let sim = max(0, 1.0 - distance / 2.0)
                totalSim += sim
                count += 1
            }
        }

        return count > 0 ? totalSim / Double(count) : 0.0
    }

    // MARK: - Phone Number Similarity

    func phoneSimilarity(_ phone1: String, _ phone2: String) -> Double {
        let normalized1 = normalizePhoneNumber(phone1)
        let normalized2 = normalizePhoneNumber(phone2)

        if normalized1 == normalized2 { return 1.0 }
        if normalized1.isEmpty || normalized2.isEmpty { return 0.0 }

        // Check if one contains the other (for international vs local)
        if normalized1.hasSuffix(normalized2) || normalized2.hasSuffix(normalized1) {
            let shorter = min(normalized1.count, normalized2.count)
            let longer = max(normalized1.count, normalized2.count)
            return Double(shorter) / Double(longer)
        }

        // Calculate digit-wise similarity
        return levenshteinSimilarity(normalized1, normalized2)
    }

    private func normalizePhoneNumber(_ phone: String) -> String {
        return phone.filter { $0.isNumber }
    }

    // MARK: - Email Similarity

    func emailSimilarity(_ email1: String, _ email2: String) -> Double {
        let e1 = email1.lowercased()
        let e2 = email2.lowercased()

        if e1 == e2 { return 1.0 }
        if e1.isEmpty || e2.isEmpty { return 0.0 }

        // Split into local and domain parts
        let parts1 = e1.split(separator: "@")
        let parts2 = e2.split(separator: "@")

        guard parts1.count == 2, parts2.count == 2 else { return 0.0 }

        let local1 = String(parts1[0])
        let local2 = String(parts2[0])
        let domain1 = String(parts1[1])
        let domain2 = String(parts2[1])

        // Same domain gets bonus
        let domainBonus = domain1 == domain2 ? 0.3 : 0.0

        // Compare local parts
        let localSim = jaroWinklerSimilarity(local1, local2) * 0.7

        return min(1.0, localSim + domainBonus)
    }

    // MARK: - Combined Name Similarity

    func nameSimilarity(firstName1: String, lastName1: String, firstName2: String, lastName2: String) -> Double {
        // Handle swapped names
        let directScore = (jaroWinklerSimilarity(firstName1, firstName2) + jaroWinklerSimilarity(lastName1, lastName2)) / 2
        let swappedScore = (jaroWinklerSimilarity(firstName1, lastName2) + jaroWinklerSimilarity(lastName1, firstName2)) / 2

        let stringScore = max(directScore, swappedScore * 0.9)

        // Add phonetic bonus
        let phoneticBonus: Double
        if soundex(firstName1) == soundex(firstName2) && soundex(lastName1) == soundex(lastName2) {
            phoneticBonus = 0.1
        } else if soundex(firstName1) == soundex(lastName2) && soundex(lastName1) == soundex(firstName2) {
            phoneticBonus = 0.08
        } else {
            phoneticBonus = 0.0
        }

        return min(1.0, stringScore + phoneticBonus)
    }
}
