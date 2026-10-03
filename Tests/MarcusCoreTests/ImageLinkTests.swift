import XCTest
@testable import MarcusCore

final class ImageLinkTests: XCTestCase {

    private let folder = URL(fileURLWithPath: "/Users/ana/Notas", isDirectory: true)

    private func file(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    private func insert(_ paths: [String], selection: String = "") -> (text: String, selection: NSRange)? {
        ImageLink.insertion(for: paths.map(file), documentFolder: folder, selection: selection)
    }

    // MARK: Destinations

    func testSameFolder() {
        XCTAssertEqual(ImageLink.destination(of: file("/Users/ana/Notas/foto.png"), from: folder), "foto.png")
    }

    func testSubfolder() {
        XCTAssertEqual(ImageLink.destination(of: file("/Users/ana/Notas/img/a/foto.png"), from: folder), "img/a/foto.png")
    }

    func testOutsideTheFolderGoesUp() {
        XCTAssertEqual(ImageLink.destination(of: file("/Users/ana/Fotos/foto.png"), from: folder), "../Fotos/foto.png")
        XCTAssertEqual(ImageLink.destination(of: file("/Volumes/USB/foto.png"), from: folder), "../../../Volumes/USB/foto.png")
    }

    /// A folder named like the file must not be taken as shared.
    func testFileNamedLikeAFolder() {
        XCTAssertEqual(ImageLink.destination(of: file("/Users/ana/Notas"), from: folder), "../Notas")
    }

    func testSpacesAndParenthesesAreEncodedAccentsAreNot() {
        XCTAssertEqual(ImageLink.destination(of: file("/Users/ana/Notas/mi foto (1).png"), from: folder),
                       "mi%20foto%20%281%29.png")
        XCTAssertEqual(ImageLink.destination(of: file("/Users/ana/Notas/año/niño.png"), from: folder), "año/niño.png")
        // Decomposed input (as the file system hands it) comes out composed.
        let decomposed = "/Users/ana/Notas/niño.png".decomposedStringWithCanonicalMapping
        XCTAssertEqual(ImageLink.destination(of: file(decomposed), from: folder), "niño.png")
        XCTAssertEqual(ImageLink.destination(of: file("/Users/ana/Notas/100%.png"), from: folder), "100%25.png")
    }

    /// What the preview and every renderer do with the destination: resolve
    /// it against the document's folder (`LinkDestination`, as the preview
    /// does). It must land on the file.
    func testDestinationResolvesBackToTheFile() throws {
        for path in ["/Users/ana/Notas/mi foto (1).png", "/Users/ana/Fotos/año/niño 2.jpg", "/Users/ana/Notas/100%.png"] {
            let destination = ImageLink.destination(of: file(path), from: folder)
            let resolved = try XCTUnwrap(LinkDestination.url(destination, relativeTo: folder))
            XCTAssertEqual(resolved.standardizedFileURL.path, path, destination)
        }
    }

    // MARK: Insertion

    func testAltFromFileNameIsSelected() throws {
        let result = try XCTUnwrap(insert(["/Users/ana/Notas/foto.png"]))
        XCTAssertEqual(result.text, "![foto](foto.png)")
        XCTAssertEqual((result.text as NSString).substring(with: result.selection), "foto")
    }

    func testSelectionBecomesTheDescription() throws {
        let result = try XCTUnwrap(insert(["/Users/ana/Notas/foto.png"], selection: "Un atardecer"))
        XCTAssertEqual(result.text, "![Un atardecer](foto.png)")
        XCTAssertEqual(result.selection, NSRange(location: (result.text as NSString).length, length: 0))
    }

    func testMultilineSelectionIsNotADescription() throws {
        let result = try XCTUnwrap(insert(["/Users/ana/Notas/foto.png"], selection: "uno\ndos"))
        XCTAssertEqual(result.text, "![foto](foto.png)")
    }

    func testBracketsInTheDescriptionAreEscaped() throws {
        let result = try XCTUnwrap(insert(["/Users/ana/Notas/plano [v2].png"]))
        XCTAssertEqual(result.text, "![plano \\[v2\\]](plano%20%5Bv2%5D.png)")
        XCTAssertEqual((result.text as NSString).substring(with: result.selection), "plano \\[v2\\]")
    }

    func testSeveralImagesOnePerLine() throws {
        let result = try XCTUnwrap(insert(["/Users/ana/Notas/a.png", "/Users/ana/Notas/b.JPG"], selection: "ignorada"))
        XCTAssertEqual(result.text, "![a](a.png)\n![b](b.JPG)")
        XCTAssertEqual(result.selection.location, (result.text as NSString).length)
    }

    func testNonImagesAreLeftOut() throws {
        XCTAssertNil(insert(["/Users/ana/Notas/informe.pdf"]))
        let result = try XCTUnwrap(insert(["/Users/ana/Notas/informe.pdf", "/Users/ana/Notas/a.webp"]))
        XCTAssertEqual(result.text, "![a](a.webp)")
    }

    func testImageExtensionsAreCaseInsensitive() {
        XCTAssertTrue(ImageLink.isImage(file("/x/A.HEIC")))
        XCTAssertTrue(ImageLink.isImage(file("/x/a.svg")))
        XCTAssertFalse(ImageLink.isImage(file("/x/a.txt")))
        XCTAssertFalse(ImageLink.isImage(URL(string: "https://example.com/a.png")!))
    }
}
