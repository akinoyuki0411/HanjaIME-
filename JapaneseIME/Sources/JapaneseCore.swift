import Foundation

struct KanaRomanizer {
    private(set) var kana = ""
    private(set) var pending = ""
    private var nCarry = false
    var display: String { kana + (nCarry ? "" : pending) }
    static let table: [String:String] = {
        var result: [String:String] = ["a":"あ","i":"い","u":"う","e":"え","o":"お","shi":"し","chi":"ち","tsu":"つ","fu":"ふ","ji":"じ","sha":"しゃ","shu":"しゅ","sho":"しょ","cha":"ちゃ","chu":"ちゅ","cho":"ちょ","ja":"じゃ","ju":"じゅ","jo":"じょ","she":"しぇ","che":"ちぇ","je":"じぇ","ti":"ち","tu":"つ","si":"し","zi":"じ","di":"ぢ","du":"づ","ye":"いぇ","wi":"うぃ","we":"うぇ","wo":"を","va":"ゔぁ","vi":"ゔぃ","vu":"ゔ","ve":"ゔぇ","vo":"ゔぉ","fa":"ふぁ","fi":"ふぃ","fe":"ふぇ","fo":"ふぉ","tsa":"つぁ","tsi":"つぃ","tse":"つぇ","tso":"つぉ"]
        for (prefix,row) in [("k","かきくけこ"),("s","さしすせそ"),("t","たちつてと"),("n","なにぬねの"),("h","はひふへほ"),("m","まみむめも"),("r","らりるれろ"),("g","がぎぐげご"),("z","ざじずぜぞ"),("d","だぢづでど"),("b","ばびぶべぼ"),("p","ぱぴぷぺぽ")] {
            for (vowel, glyph) in zip("aiueo",row) {result[prefix+String(vowel)] = String(glyph)}
        }
        for (prefix,glyph) in [("ky","き"),("gy","ぎ"),("sy","し"),("zy","じ"),("ty","ち"),("dy","ぢ"),("ny","に"),("hy","ひ"),("by","び"),("py","ぴ"),("my","み"),("ry","り")] { for (vowel,small) in zip("auo","ゃゅょ") { result[prefix+String(vowel)] = glyph+String(small) } }
        for (key,value) in ["ya":"や","yu":"ゆ","yo":"よ","wa":"わ","xa":"ぁ","xi":"ぃ","xu":"ぅ","xe":"ぇ","xo":"ぉ","xya":"ゃ","xyu":"ゅ","xyo":"ょ","xtu":"っ","xtsu":"っ","xwa":"ゎ","xka":"ゕ","xke":"ゖ"] { result[key]=value; if key.hasPrefix("x") {result["l"+key.dropFirst()]=value} }
        return result
    }()
    mutating func append(_ character: Character) {
        if character == "-" { flush(); kana += "ー"; return }
        if nCarry {
            if !"aiueoyn".contains(character) { pending = "" }
            nCarry = false
        }
        pending += String(character).lowercased()
        consume()
    }
    private mutating func consume() {
        while !pending.isEmpty {
            if let value = Self.table[pending] {kana += value; pending=""; return}
            let chars=Array(pending)
            if chars.count >= 2, chars[0] == "n", chars[1] == "'" {kana += "ん";pending=String(chars.dropFirst(2));continue}
            if chars.count >= 2, chars[0] == "n", !"aiueoyn".contains(chars[1]) {kana += "ん";pending=String(chars.dropFirst());continue}
            if chars.count >= 2, chars[0] == chars[1], chars[0] != "n", "bcdfghjklmpqrstvwxyz".contains(chars[0]) {kana += "っ";pending=String(chars.dropFirst());continue}
            if pending == "nn" {kana += "ん";pending="n";nCarry=true;return}
            if Self.table.keys.contains(where:{$0.hasPrefix(pending)}) || pending == "n" {return}
            // Unsupported sequences remain visible instead of dropping input.
            kana += String(chars[0]); pending=String(chars.dropFirst())
        }
    }
    mutating func flush() { if pending == "n" && !nCarry {kana += "ん"} else if nCarry {pending=""} else {kana += pending};pending="";nCarry=false }
    mutating func backspace() {if nCarry {pending="";nCarry=false;if !kana.isEmpty {kana.removeLast()}} else if !pending.isEmpty {pending.removeLast()} else if !kana.isEmpty {kana.removeLast()}}
    mutating func clear() {kana="";pending="";nCarry=false}
    func katakana() -> String { display.applyingTransform(StringTransform("Hiragana-Katakana"), reverse:false) ?? display }
}

struct JapaneseCandidate: Equatable {
    let text: String
    let label: String
}

final class JapaneseDictionary {
    private(set) var entries: [String:[String]] = [:]
    let oldForms: [UInt32:String]
    init(dictionary: URL, oldMap: URL) throws {
        let text = try String(contentsOf:dictionary,encoding:.utf8)
        for line in text.split(separator:"\n") where !line.hasPrefix(";") {
            guard let split=line.firstIndex(of:" ") else {continue}
            let key=String(line[..<split]); let values=line[line.index(after:split)...].split(separator:"/").compactMap {part->String? in
                let value=String(part.split(separator:";",maxSplits:1,omittingEmptySubsequences:false)[0])
                guard !value.isEmpty, !value.contains("["), !value.contains("]"), !value.hasPrefix("("), !value.contains("#"), !value.contains("\\") else {return nil}
                return value
            }
            if !values.isEmpty {entries[key]=values}
        }
        let map=try JSONDecoder().decode([String:String].self,from:Data(contentsOf:oldMap))
        oldForms=Dictionary(uniqueKeysWithValues:map.compactMap {key,value in guard key.count==1,value.count==1 else{return nil};return(key.unicodeScalars.first!.value,value)})
    }
    func old(_ value:String)->String {value.unicodeScalars.map{oldForms[$0.value] ?? String($0)}.joined()}
    func candidates(_ reading:String)->[JapaneseCandidate] {
        var values=entries[reading] ?? []
        // SKK okuri entries describe the stem plus the first consonant of its suffix.
        let chars=Array(reading)
        if chars.count > 1 {
            for split in 1..<chars.count {
                let suffix=String(chars[split...]); let stem=String(chars[..<split])
                if let syllable=KanaRomanizer.table.keys.filter({KanaRomanizer.table[$0] == String(chars[split]) && $0.count <= 3}).sorted(by:{$0.count < $1.count}).first,
                   let consonant=syllable.first, !"aiueo".contains(consonant),let matches=entries[stem+String(consonant)] {
                    values += matches.prefix(12).map{$0+suffix}
                }
            }
        }
        let extras:[String:[String]]=["ほし":["★","☆"],"はーと":["♥","♡"],"やじるし":["←","→","↑","↓","↔"],"まる":["○","●","◎"],"かっこ":["「」","『』","（）","【】"]]
        let symbols=values.filter { !$0.unicodeScalars.contains { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) } } + (extras[reading] ?? [])
        values.removeAll { symbols.contains($0) }
        var result:[JapaneseCandidate]=[];var seen=Set<Data>()
        // Old forms retain lexical dictionary order; simplified equivalents come after them.
        for value in values {let text=old(value);if seen.insert(Data(text.utf8)).inserted {result.append(JapaneseCandidate(text:text,label:Data(text.utf8) != Data(value.utf8) ? "旧字体" : "漢字"))}}
        for value in values where Data(old(value).utf8) != Data(value.utf8) {if seen.insert(Data(value.utf8)).inserted {result.append(JapaneseCandidate(text:value,label:"新字体"))}}
        for value in symbols {if seen.insert(Data(value.utf8)).inserted {result.append(JapaneseCandidate(text:value,label:"記号"))}}
        if seen.insert(Data(reading.utf8)).inserted {result.append(JapaneseCandidate(text:reading,label:"ひらがな"))}
        let katakana=reading.applyingTransform(StringTransform("Hiragana-Katakana"),reverse:false) ?? reading
        if seen.insert(Data(katakana.utf8)).inserted {result.append(JapaneseCandidate(text:katakana,label:"カタカナ"))}
        return Array(result.prefix(80))
    }
}
