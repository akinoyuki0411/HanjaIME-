import Foundation
@main struct Tests {
 static func main() {
  var count=0
  func check(_ value: Bool,_ name:String) { guard value else { fputs("FAIL \(name)\n",stderr);exit(1) };count+=1 }
  var v=[Float](repeating:0,count:128);v[0]=1
  let t=FaceTemplate(model:FaceTemplate.model,samples:[v,v,v])
  check(FacePolicy.matches(v,template:t),"matching embedding")
  var other=v;other[0]=0;other[1]=1
  check(!FacePolicy.matches(other,template:t),"unrelated face rejected")
  check(FacePolicy.enrollmentIsConsistent(t), "consistent registration accepted")
  check(!FacePolicy.enrollmentIsConsistent(FaceTemplate(model:FaceTemplate.model,samples:[v,v,other])), "inconsistent direction samples rejected without lowering identity threshold")
  check(!FacePolicy.valid([Float](repeating:0,count:128)),"zero rejected")
  check(!FacePolicy.valid([Float](repeating:.nan,count:128)),"nan rejected")
  check(!FacePolicy.matches(v,template:FaceTemplate(model:"different",samples:[v,v,v])),"model mismatch rejected")
  var c=FaceChallenge(now:0,direction:1)
  for i in 0..<3 { c.observe(matches:true,yaw:0,now:Double(i)*0.3) }
  check(c.stage == .turn,"center before turn")
  for i in 3..<6 { c.observe(matches:true,yaw:0.4,now:Double(i)*0.3) }
  check(c.stage == .returnToCenter,"turn before return")
  for i in 6..<9 { c.observe(matches:true,yaw:0,now:Double(i)*0.3) }
  check(c.stage == .passed,"temporal challenge")
  var photo=FaceChallenge(now:0,direction:1)
  for i in 0..<60 { photo.observe(matches:true,yaw:0,now:Double(i)*0.31) }
  check(photo.stage == .failed,"static frame never satisfies turn")
  var missing=FaceChallenge(now:0);missing.observe(matches:false,yaw:0,now:0.1)
  check(missing.stage == .failed,"lost or changed identity fails")
  var gate=UnlockAttemptGate();gate.locked();let epoch=gate.epoch!
  check(!gate.claim(epoch:epoch,challenge:c,enabled:true,sessionIsOwner:true,targetVerified:false),"wrong target blocked")
  check(!gate.claim(epoch:epoch,challenge:c,enabled:false,sessionIsOwner:true,targetVerified:true),"disabled blocked")
  check(gate.claim(epoch:epoch,challenge:c,enabled:true,sessionIsOwner:true,targetVerified:true),"one attempt allowed")
  check(!gate.claim(epoch:epoch,challenge:c,enabled:true,sessionIsOwner:true,targetVerified:true),"repeat blocked")
  gate.locked();check(gate.attempted,"duplicate lock notification cannot rearm")
  gate.unlocked();gate.locked();check(gate.epoch != epoch,"new lock epoch")
  print("PASS: \(count) face policy checks; synthetic vectors do not validate biometric accuracy")
 }
}
