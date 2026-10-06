import Foundation
var checks=0
func check(_ value:Bool,_ message:String) {checks += 1;if !value {fatalError(message)}}
for (input,expected) in [("gakkou","がっこう"),("tenki","てんき"),("rekishi","れきし"),("nihon","にほん"),("nihonn","にほん"),("konnichiha","こんにちは"),("kansha","かんしゃ"),("kannsha","かんしゃ"),("n'ya","んや"),("kya","きゃ"),("kitte","きって"),("xtsu","っ")] {
 var roman=KanaRomanizer();for c in input {roman.append(c)};roman.flush();check(roman.display==expected,"\(input): \(roman.display) != \(expected)")
}
var roman=KanaRomanizer();roman.append("k");roman.backspace();check(roman.display.isEmpty,"pending backspace")
roman.append("n");roman.append("n");roman.backspace();check(roman.display.isEmpty,"nn backspace")
let root=URL(fileURLWithPath:CommandLine.arguments[1])
let dictionary=try JapaneseDictionary(dictionary:root.appendingPathComponent("SKK-JISYO.L.utf8"),oldMap:root.appendingPathComponent("OldForms.json"))
for (reading,old,new) in [("がっこう","學校","学校"),("てんき","天氣","天気"),("れきし","歷史","歴史")] {
 let values=dictionary.candidates(reading).map{$0.text}
 check(values.contains(old),"missing \(old)");check(values.contains(new),"missing \(new)");check(values.firstIndex(of:old)! < values.firstIndex(of:new)!,"old order")
}
check(dictionary.candidates("たべる").contains(where:{$0.text=="食べる"}),"okuri")
let values=dictionary.candidates("かみ").map{Data($0.text.utf8)}
check(values.contains(Data("神".utf8)) && values.contains(Data("神".utf8)),"compatibility forms distinct")
check(dictionary.entries.values.allSatisfy{$0.allSatisfy{!$0.isEmpty && !$0.contains("]")}},"clean entries")
check(dictionary.candidates("ほし").contains(where:{$0.text=="★" && $0.label=="記号"}),"star symbol category")
check(dictionary.candidates("やじるし").contains(where:{$0.text=="→" && $0.label=="記号"}),"arrow symbol category")
print("Japanese core: \(checks) checks passed, \(dictionary.entries.count) readings")
