// 인트로 히트 글로우 PNG 생성 — `swift scripts/render-intro-heat.swift`
//
// 아이콘(docs/store-v2/icon-v2/final/final.svg)의 블러 타원 9개를 투명 배경에 그대로 렌더한다.
// 런타임에 Canvas 블러로 그리면 첫 래스터화가 메인 스레드를 막아 인트로 선 애니메이션이 멈췄다
// (2026-10-03 시뮬레이터 녹화로 확인). 그래서 미리 구운 이미지를 쓴다.
// 캔버스 = 아이콘 x 0…1024, y 140…910 영역 + 사방 320 여백(IntroView 의 FCScopeMark.heatPad/viewY/viewH).
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Blob { let cx, cy, rx, ry: CGFloat; let hex: UInt32; let a: CGFloat; let blur: CGFloat }
let blobs: [Blob] = [
    Blob(cx: 520, cy: 580, rx: 420, ry: 250, hex: 0x4A1FD6, a: 0.85, blur: 110),
    Blob(cx: 300, cy: 660, rx: 150, ry: 100, hex: 0x6A2BE0, a: 0.60, blur: 80),
    Blob(cx: 525, cy: 580, rx: 270, ry: 165, hex: 0xE0218A, a: 0.95, blur: 80),
    Blob(cx: 700, cy: 450, rx: 150, ry: 90, hex: 0xE0218A, a: 0.85, blur: 60),
    Blob(cx: 525, cy: 572, rx: 190, ry: 115, hex: 0xFF5A26, a: 1.00, blur: 60),
    Blob(cx: 702, cy: 448, rx: 90, ry: 56, hex: 0xFF7A2E, a: 0.95, blur: 45),
    Blob(cx: 525, cy: 565, rx: 112, ry: 70, hex: 0xFFC23A, a: 1.00, blur: 45),
    Blob(cx: 703, cy: 446, rx: 38, ry: 26, hex: 0xFFD65A, a: 0.90, blur: 30),
    Blob(cx: 525, cy: 560, rx: 52, ry: 34, hex: 0xFFF3C2, a: 1.00, blur: 28),
]
let pad: CGFloat = 320, viewY: CGFloat = 140, viewH: CGFloat = 770
let scale: CGFloat = 0.75
let W = Int((1024 + 2 * pad) * scale), H = Int((viewH + 2 * pad) * scale)
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ci = CIContext(options: [.workingColorSpace: cs, .outputColorSpace: cs])

func render(outerAlpha: CGFloat, to path: String) {
    let rect = CGRect(x: 0, y: 0, width: W, height: H)
    var acc = CIImage(color: .clear).cropped(to: rect)
    for (i, b) in blobs.enumerated() {
        let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let a = i < 2 ? b.a * outerAlpha : b.a
        ctx.setFillColor(red: CGFloat((b.hex >> 16) & 0xFF) / 255, green: CGFloat((b.hex >> 8) & 0xFF) / 255,
                         blue: CGFloat(b.hex & 0xFF) / 255, alpha: a)
        // CG 원점은 왼쪽 아래 — y 를 뒤집는다
        let x = (b.cx - b.rx + pad) * scale
        let yTop = (b.cy - b.ry - viewY + pad) * scale
        let h = 2 * b.ry * scale
        ctx.fillEllipse(in: CGRect(x: x, y: CGFloat(H) - yTop - h, width: 2 * b.rx * scale, height: h))
        let blurred = CIImage(cgImage: ctx.makeImage()!)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(b.blur * scale))
            .cropped(to: rect)
        // clampedToExtent 는 투명 가장자리를 늘리므로 영향 없음
        acc = blurred.composited(over: acc)
    }
    let cg = ci.createCGImage(acc, from: rect, format: .RGBA8, colorSpace: cs)!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, cg, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(path) \(W)x\(H)")
}

let dir = "FCScope/Resources/Assets.xcassets/IntroHeat.imageset"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
render(outerAlpha: 1, to: "\(dir)/IntroHeat-dark.png")
// 라이트 배경에서는 바깥 바이올렛이 얼룩처럼 무거워 보여 바깥층만 덜어낸다.
render(outerAlpha: 0.55, to: "\(dir)/IntroHeat-light.png")
