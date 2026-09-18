#!/usr/bin/env swift
//
//  make_icon.swift — genera l'icona dell'app (1024x1024 PNG, senza canale alpha).
//
//  Uso:
//      swift scripts/make_icon.swift [percorso/output.png]
//
//  Default: App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
//
//  Perché uno script e non un file binario "misterioso": l'icona è riproducibile,
//  versionabile e modificabile senza Xcode, Figma o tool esterni. Usa solo
//  CoreGraphics + ImageIO, già presenti nelle Command Line Tools (SPEC §1.2).
//
//  Disegno (vedi docs/DESIGN.md):
//    - fondo scuro con gradiente verticale quasi-nero/indaco
//    - tre macchie radiali sfocate (lavanda, pesca, indaco freddo) — la sfocatura
//      è ottenuta con gradienti radiali che sfumano ad alpha 0, senza CoreImage
//    - glifo bilanciere bianco minimale, geometrico, centrato
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Parametri

let side = 1024
let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png")

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(a)])!
}

// MARK: - Contesto (opaco: le icone iOS non possono avere canale alpha)

guard let ctx = CGContext(
    data: nil,
    width: side,
    height: side,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: space,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    FileHandle.standardError.write(Data("make_icon: impossibile creare il contesto grafico\n".utf8))
    exit(1)
}

let size = CGFloat(side)
ctx.interpolationQuality = .high
ctx.setAllowsAntialiasing(true)

// MARK: - Fondo: gradiente verticale

let background = CGGradient(
    colorsSpace: space,
    colors: [
        rgb(0.13, 0.12, 0.19),  // indaco profondo (in alto)
        rgb(0.09, 0.09, 0.13),
        rgb(0.05, 0.05, 0.07)   // quasi nero (in basso)
    ] as CFArray,
    locations: [0.0, 0.55, 1.0]
)!
ctx.drawLinearGradient(
    background,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: 0, y: 0),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)

// MARK: - Macchie sfocate

/// Disegna una macchia morbida: gradiente radiale che sfuma fino ad alpha 0.
func blob(center: CGPoint, radius: CGFloat, color: (Double, Double, Double), alpha: Double) {
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [
            rgb(color.0, color.1, color.2, alpha),
            rgb(color.0, color.1, color.2, alpha * 0.55),
            rgb(color.0, color.1, color.2, alpha * 0.16),
            rgb(color.0, color.1, color.2, 0.0)
        ] as CFArray,
        locations: [0.0, 0.42, 0.72, 1.0]
    )!
    ctx.saveGState()
    ctx.setBlendMode(.plusLighter)
    ctx.drawRadialGradient(
        gradient,
        startCenter: center, startRadius: 0,
        endCenter: center, endRadius: radius,
        options: []
    )
    ctx.restoreGState()
}

// Lavanda in alto a sinistra, pesca in basso a destra, indaco freddo a bilanciare.
blob(center: CGPoint(x: size * 0.26, y: size * 0.78), radius: size * 0.60,
     color: (0.62, 0.53, 0.98), alpha: 0.56)
blob(center: CGPoint(x: size * 0.80, y: size * 0.24), radius: size * 0.56,
     color: (1.00, 0.70, 0.54), alpha: 0.50)
blob(center: CGPoint(x: size * 0.88, y: size * 0.84), radius: size * 0.40,
     color: (0.40, 0.48, 0.96), alpha: 0.30)

// Vignettatura: riporta i bordi verso lo scuro così il glifo resta leggibile.
let vignette = CGGradient(
    colorsSpace: space,
    colors: [
        rgb(0, 0, 0, 0.0),
        rgb(0, 0, 0, 0.08),
        rgb(0, 0, 0, 0.32)
    ] as CFArray,
    locations: [0.45, 0.72, 1.0]
)!
ctx.drawRadialGradient(
    vignette,
    startCenter: CGPoint(x: size / 2, y: size / 2), startRadius: 0,
    endCenter: CGPoint(x: size / 2, y: size / 2), endRadius: size * 0.78,
    options: [.drawsAfterEndLocation]
)

// MARK: - Glifo: bilanciere

let cx = size / 2
let cy = size / 2

/// Rettangolo arrotondato centrato in (x, y).
func bar(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, radius: CGFloat) -> CGPath {
    CGPath(
        roundedRect: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h),
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    )
}

// Alone morbido dietro al glifo: lo stacca dal fondo senza usare un'ombra netta.
blob(center: CGPoint(x: cx, y: cy), radius: size * 0.40, color: (1, 1, 1), alpha: 0.10)

ctx.saveGState()

// Asta
ctx.setFillColor(rgb(1, 1, 1, 0.92))
ctx.addPath(bar(x: cx, y: cy, w: 544, h: 36, radius: 18))
ctx.fillPath()

// Dischi: due per lato, interni più alti, esterni più corti.
ctx.setFillColor(rgb(1, 1, 1, 1.0))
for sign in [CGFloat(-1), CGFloat(1)] {
    ctx.addPath(bar(x: cx + sign * 150, y: cy, w: 54, h: 220, radius: 16))
    ctx.addPath(bar(x: cx + sign * 224, y: cy, w: 46, h: 150, radius: 14))
}
ctx.fillPath()

ctx.restoreGState()

// MARK: - Scrittura PNG

guard let image = ctx.makeImage() else {
    FileHandle.standardError.write(Data("make_icon: rendering fallito\n".utf8))
    exit(1)
}

try? FileManager.default.createDirectory(
    at: output.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

guard let destination = CGImageDestinationCreateWithURL(
    output as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    FileHandle.standardError.write(Data("make_icon: impossibile scrivere su \(output.path)\n".utf8))
    exit(1)
}

CGImageDestinationAddImage(destination, image, [
    kCGImagePropertyHasAlpha: false,
    kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGInterlaceType: 0]
] as CFDictionary)

guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("make_icon: finalize fallito\n".utf8))
    exit(1)
}

print("make_icon: scritta icona \(side)x\(side) → \(output.path)")
