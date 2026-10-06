import Foundation
@main struct LanguageTests {
 static func main() {
  defer { UserDefaults.standard.removeObject(forKey: "hanjime.language") }
  UserDefaults.standard.set("ko", forKey: "hanjime.language")
  precondition(HL("General") == "일반")
  precondition(HL("Shelf") == "파일 보관함")
  precondition(HL("Flip preview horizontally (mirror)") == "좌우 반전 · 거울 모드")
  UserDefaults.standard.set("en", forKey: "hanjime.language")
  precondition(HL("General") == "General")
  precondition(HL("Quit Atoll") == "Quit HanjiME Notch")
  precondition(HL("A user note") == "A user note")
  print("PASS: 6 language and branding checks")
 }
}
