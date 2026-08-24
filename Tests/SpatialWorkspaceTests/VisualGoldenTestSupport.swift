import AppKit
import SwiftUI
import XCTest

@MainActor
enum VisualGoldenTestSupport {
    struct Comparison {
        let meanChannelDifference: Double
        let changedPixelFraction: Double
    }

    private struct Raster {
        let width: Int
        let height: Int
        let bytes: [UInt8]
    }

    static func assertView<V: View>(
        named name: String,
        size: CGSize,
        scale: CGFloat = 1,
        meanDifferenceLimit: Double = 0.006,
        changedPixelLimit: Double = 0.04,
        file: StaticString = #filePath,
        line: UInt = #line,
        @ViewBuilder content: () -> V
    ) throws {
        let actualData = try hostedImageData(
            content()
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark),
            size: size,
            scale: scale
        )
        let goldenDirectory = visualGoldenDirectory(relativeTo: file)
        let goldenURL = goldenDirectory.appendingPathComponent(goldenFilename(for: name))

        if ProcessInfo.processInfo.environment["UPDATE_VISUAL_GOLDENS"] == "1" {
            try FileManager.default.createDirectory(at: goldenDirectory, withIntermediateDirectories: true)
            try actualData.write(to: goldenURL, options: Data.WritingOptions.atomic)
            return
        }

        guard FileManager.default.fileExists(atPath: goldenURL.path) else {
            XCTFail(
                "Missing visual golden \(goldenURL.path). Run UPDATE_VISUAL_GOLDENS=1 swift test --filter WorkspaceVisualRegressionTests, then review every image.",
                file: file,
                line: line
            )
            return
        }

        let expectedData = try Data(contentsOf: goldenURL)
        let expected = try raster(from: expectedData)
        let actual = try raster(from: actualData)
        guard expected.width == actual.width, expected.height == actual.height else {
            try writeFailureArtifacts(name: name, actual: actualData, diff: nil, relativeTo: file)
            XCTFail(
                "Visual golden dimensions changed for \(name): expected \(expected.width)x\(expected.height), actual \(actual.width)x\(actual.height).",
                file: file,
                line: line
            )
            return
        }

        let comparison = compare(expected: expected, actual: actual)
        guard comparison.meanChannelDifference <= meanDifferenceLimit,
              comparison.changedPixelFraction <= changedPixelLimit else {
            let diffData = try differencePNG(expected: expected, actual: actual)
            let artifacts = try writeFailureArtifacts(
                name: name,
                actual: actualData,
                diff: diffData,
                relativeTo: file
            )
            XCTFail(
                String(
                    format: "Visual golden mismatch for %@: mean %.4f (limit %.4f), changed pixels %.2f%% (limit %.2f%%). Review %@.",
                    name,
                    comparison.meanChannelDifference,
                    meanDifferenceLimit,
                    comparison.changedPixelFraction * 100,
                    changedPixelLimit * 100,
                    artifacts.path
                ),
                file: file,
                line: line
            )
            return
        }
    }

    private static func visualGoldenDirectory(relativeTo file: StaticString) -> URL {
        URL(fileURLWithPath: String(describing: file))
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("VisualGoldens", isDirectory: true)
    }

    private static func goldenFilename(for name: String) -> String {
        guard let variant = ProcessInfo.processInfo.environment["COMMANDHALL_VISUAL_GOLDEN_VARIANT"],
              !variant.isEmpty else {
            return "\(name).jpg"
        }

        precondition(
            variant.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") },
            "Visual golden variants may contain only ASCII letters, numbers, hyphens, and underscores."
        )
        return "\(name).\(variant).jpg"
    }

    private static func hostedImageData<V: View>(_ view: V, size: CGSize, scale: CGFloat) throws -> Data {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.contentView = host
        window.orderBack(nil)
        defer {
            window.contentView = nil
            window.close()
        }

        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        let pixelWidth = max(1, Int((size.width * scale).rounded()))
        let pixelHeight = max(1, Int((size.height * scale).rounded()))
        let representation = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelWidth,
                pixelsHigh: pixelHeight,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: NSColorSpaceName.deviceRGB,
                bytesPerRow: pixelWidth * 4,
                bitsPerPixel: 32
            )
        )
        representation.size = size
        host.cacheDisplay(in: host.bounds, to: representation)
        return try XCTUnwrap(
            representation.representation(
                using: NSBitmapImageRep.FileType.jpeg,
                properties: [.compressionFactor: 0.88]
            )
        )
    }

    private static func raster(from data: Data) throws -> Raster {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(
            CGContext(
                data: &bytes,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Raster(width: width, height: height, bytes: bytes)
    }

    private static func compare(expected: Raster, actual: Raster) -> Comparison {
        var totalDifference = 0
        var changedPixels = 0
        let pixelCount = expected.width * expected.height

        for pixel in 0 ..< pixelCount {
            let offset = pixel * 4
            var maximumDifference = 0
            for channel in 0 ..< 3 {
                let difference = abs(Int(expected.bytes[offset + channel]) - Int(actual.bytes[offset + channel]))
                totalDifference += difference
                maximumDifference = max(maximumDifference, difference)
            }
            if maximumDifference > 16 { changedPixels += 1 }
        }

        return Comparison(
            meanChannelDifference: Double(totalDifference) / Double(pixelCount * 3 * 255),
            changedPixelFraction: Double(changedPixels) / Double(pixelCount)
        )
    }

    private static func differencePNG(expected: Raster, actual: Raster) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: expected.bytes.count)
        for pixel in 0 ..< expected.width * expected.height {
            let offset = pixel * 4
            for channel in 0 ..< 3 {
                let difference = abs(Int(expected.bytes[offset + channel]) - Int(actual.bytes[offset + channel]))
                bytes[offset + channel] = UInt8(min(255, difference * 5))
            }
            bytes[offset + 3] = 255
        }

        let representation = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: expected.width,
                pixelsHigh: expected.height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: NSColorSpaceName.deviceRGB,
                bytesPerRow: expected.width * 4,
                bitsPerPixel: 32
            )
        )
        let destination = try XCTUnwrap(representation.bitmapData)
        bytes.withUnsafeBytes { source in
            guard let sourceAddress = source.baseAddress else { return }
            destination.update(from: sourceAddress.assumingMemoryBound(to: UInt8.self), count: bytes.count)
        }
        return try XCTUnwrap(representation.representation(using: NSBitmapImageRep.FileType.png, properties: [:]))
    }

    @discardableResult
    private static func writeFailureArtifacts(
        name: String,
        actual: Data,
        diff: Data?,
        relativeTo file: StaticString
    ) throws -> URL {
        let directory = visualGoldenDirectory(relativeTo: file)
            .appendingPathComponent("Failures", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try actual.write(to: directory.appendingPathComponent("\(name).actual.jpg"), options: .atomic)
        if let diff {
            try diff.write(to: directory.appendingPathComponent("\(name).diff.png"), options: .atomic)
        }
        return directory
    }
}
