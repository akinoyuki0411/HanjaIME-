import SwiftUI

struct FaceEnrollmentView: View {
    @ObservedObject var model: FaceService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let green = Color(red: 0.25, green: 0.88, blue: 0.54)
    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(green.opacity(0.07))
                if model.enrollmentStep == "capture" {
                    FacePreview(session: model.camera.session).clipShape(Circle()).padding(15)
                } else {
                    Image(systemName: model.enrollmentStep == "complete" ? "checkmark" : model.enrollmentStep == "failed" ? "exclamationmark" : "faceid")
                        .font(.system(size: 48, weight: .light)).foregroundStyle(green)
                }
                ForEach(0..<72, id: \.self) { index in
                    Capsule().fill(index < model.enrollmentProgress * 8 ? green : green.opacity(0.18))
                        .frame(width: 3, height: index % 8 == 0 ? 14 : 9)
                        .offset(y: -82).rotationEffect(.degrees(Double(index) * 5))
                }
                if model.enrollmentStep == "capture" {
                    Image(systemName: model.pose.symbol).font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.black).frame(width: 42, height: 42).background(green, in: Circle()).offset(y: 67)
                }
            }.frame(width: 176, height: 176)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: model.enrollmentProgress)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("얼굴 등록 \(model.enrollmentProgress)/9 단계")
            VStack(spacing: 10) {
                Text(title).font(.title3.bold()).multilineTextAlignment(.center)
                Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 300)
            }.frame(minHeight: 72)
            if model.enrollmentStep == "capture" {
                Text(model.cameraState).font(.caption2).foregroundStyle(.secondary)
                Text("\(model.enrollmentProgress) / 9 방향 완료").font(.caption.monospacedDigit()).foregroundStyle(green)
            }
            Spacer(minLength: 0)
            HStack {
                Button(model.enrollmentStep == "complete" ? "닫기" : "나중에") { model.closeEnrollment() }
                Spacer()
                if ["intro", "failed"].contains(model.enrollmentStep) {
                    Button(model.enrollmentStep == "intro" ? "시작하기" : "다시 시도") { model.enroll() }.buttonStyle(EnrollmentPrimaryButton())
                } else if model.enrollmentStep == "complete" {
                    Button("완료") { model.closeEnrollment() }.buttonStyle(EnrollmentPrimaryButton())
                } else if model.enrollmentStep == "authorizing" { ProgressView().controlSize(.small) }
            }
        }.padding(20).frame(width: 340, height: 408)
    }
    private var title: String {
        switch model.enrollmentStep {
        case "capture": return model.pose.label
        case "complete": return "얼굴 등록 완료"
        case "failed": return "등록을 마치지 못했어요"
        case "authorizing": return "본인 확인 중"
        default: return "얼굴을 등록하세요"
        }
    }
    private var detail: String {
        switch model.enrollmentStep {
        case "intro": return "밝은 곳에서 화살표를 따라 고개를 조금씩 움직여 주세요. 정면과 8방향을 확인합니다."
        case "complete": return "얼굴 특징을 이 Mac의 키체인에 저장했습니다. 원본 사진은 저장하지 않습니다."
        default: return model.status
        }
    }
}

private struct EnrollmentPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold)).foregroundStyle(.black)
            .padding(.horizontal, 18).padding(.vertical, 9)
            .background(Color(red: 0.25, green: 0.88, blue: 0.54).opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}
