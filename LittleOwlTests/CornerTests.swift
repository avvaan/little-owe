import SpriteKit
import XCTest
@testable import LittleOwl

/// The basket in the corner, and the split it makes with the window.
///
/// The window and the basket ask the same bank of questions from opposite ends: at the
/// window the child asks and the owl answers, and at the basket the owl offers and the
/// child picks. What is worth testing is not which of them is nicer but that they
/// really are two separate things a child can reach, that neither of them lands on top
/// of the other on the screen, and that the cards in both of them have pictures on.
final class CornerTests: XCTestCase {

    // MARK: The prop

    func testTheBasketIsItsOwnPropWithItsOwnMode() {
        XCTAssertTrue(RoomObjectID.allCases.contains(.basket))
        XCTAssertNotEqual(RoomObjectID.basket.modeDescription,
                          RoomObjectID.window.modeDescription,
                          "the two halves must not read as the same mode to a parent")
    }

    /// The basket is the one prop that is not in the painting, so it is the one prop
    /// that can be missing. A missing texture is a red cross on the screen, which has
    /// already reached a child's iPad once.
    func testAMissingBasketPaintingMeansNoBasketRatherThanARedCross() {
        if ArtTexture.exists("corner_basket") {
            XCTAssertNotNil(RoomBuilder.makeBasket())
        } else {
            XCTAssertNil(RoomBuilder.makeBasket(),
                         "the basket was built without a painting to build it from")
        }
    }

    // MARK: Where it sits

    /// `.aspectFill` on the narrowest supported iPad (1133 × 744) scales the 1366 × 1024
    /// scene by 1133/1366 = 0.829, which leaves 1024 − 744/0.829 = 127 points of height
    /// to lose, 63 or so off each end. Anything a child has to hit must clear that.
    func testTheBasketIsReachableOnTheNarrowestIPad() {
        let lost: CGFloat = 64

        let object = RoomObject(
            id: .basket,
            content: nil,
            localBounds: CGRect(origin: .zero, size: RoomLayout.basketSize)
                .offsetBy(dx: -RoomLayout.basketSize.width / 2,
                          dy: -RoomLayout.basketSize.height / 2),
            feedback: .squash
        )
        object.position = RoomLayout.basketCentre

        let target = object.hitAreaInParent
        XCTAssertGreaterThanOrEqual(target.minY, lost,
                                    "the bottom of the basket's tap target is cropped away")
        XCTAssertLessThanOrEqual(target.maxY, RoomLayout.designSize.height - lost)
        XCTAssertGreaterThanOrEqual(target.minX, 0)
        XCTAssertLessThanOrEqual(target.maxX, RoomLayout.designSize.width)
    }

    /// 88 points on the device, which is the brief's floor and the reason
    /// `minimumTapTarget` is 120 design points rather than 88.
    func testTheBasketIsBigEnoughToHit() {
        XCTAssertGreaterThanOrEqual(RoomLayout.basketSize.width, RoomLayout.minimumTapTarget)
        XCTAssertGreaterThanOrEqual(RoomLayout.basketSize.height, RoomLayout.minimumTapTarget)
    }

    /// `basketSize` is the whole sprite including its shadow, and `RoomBuilder` scales
    /// the sprite by height with the painting's own aspect. If the two disagree the
    /// basket is drawn narrower or wider than the box a child is aiming at, which is the
    /// kind of thing that looks fine in a screenshot and is wrong under a finger.
    func testTheTapTargetIsTheSizeOfThePaintingItIsOn() throws {
        let texture = try XCTUnwrap(ArtTexture.texture(named: "corner_basket"))
        let painted = texture.size().width / texture.size().height
        let declared = RoomLayout.basketSize.width / RoomLayout.basketSize.height
        XCTAssertEqual(painted, declared, accuracy: 0.02,
                       "RoomLayout.basketSize is \(declared) wide to tall, the painting is \(painted)")
    }

    func testTheBasketDoesNotSitUnderAnythingElse() {
        let basket = CGRect(origin: .zero, size: RoomLayout.basketSize)
            .offsetBy(dx: RoomLayout.basketCentre.x - RoomLayout.basketSize.width / 2,
                      dy: RoomLayout.basketCentre.y - RoomLayout.basketSize.height / 2)

        let rug = CGRect(origin: .zero, size: RoomLayout.rugSize)
            .offsetBy(dx: RoomLayout.rugCentre.x - RoomLayout.rugSize.width / 2,
                      dy: RoomLayout.rugCentre.y - RoomLayout.rugSize.height / 2)
        XCTAssertFalse(basket.intersects(rug), "the basket is standing on the rug")

        let window = CGRect(origin: .zero, size: RoomLayout.windowTapSize)
            .offsetBy(dx: RoomLayout.windowCentre.x - RoomLayout.windowTapSize.width / 2,
                      dy: RoomLayout.windowCentre.y - RoomLayout.windowTapSize.height / 2)
        XCTAssertFalse(basket.intersects(window))

        // The corner badge that swaps the animal lives in the *top* right.
        let badge = CGRect(x: CharacterPicker.centre.x - CharacterPicker.diameter / 2,
                           y: CharacterPicker.centre.y - CharacterPicker.diameter / 2,
                           width: CharacterPicker.diameter, height: CharacterPicker.diameter)
        XCTAssertFalse(basket.intersects(badge))
    }

    // MARK: Where the owl and the cards go

    /// Three cards are 968 points wide. The owl stands by the basket while they are up,
    /// and a child aiming at the right-hand card must not be aiming at the owl.
    func testTheCardsAndTheOwlDoNotOverlapAtTheBasket() {
        let pack = try? ContentLoader.load()
        XCTAssertNotNil(pack, "no content pack to build the mode from")
        guard let pack else { return }

        let scene = SKScene(size: RoomLayout.designSize)
        let owl = OwlNode(rig: WatercolourOwlRig(character: .owl))
        let mode = WonderMode(scene: scene, owl: owl, pack: pack, voice: OwlVoice(pack: pack))

        let rowWidth = ChoiceRow.rowWidth(mode.choiceCount)
        let cards = CGRect(x: mode.cardsCentre.x - rowWidth / 2,
                           y: mode.cardsCentre.y - ChoiceRow.cardSize.height / 2,
                           width: rowWidth, height: ChoiceRow.cardSize.height)

        XCTAssertGreaterThanOrEqual(cards.minX, 0)
        XCTAssertLessThanOrEqual(cards.maxX, RoomLayout.designSize.width)
        XCTAssertGreaterThanOrEqual(cards.minY, 64, "the bottom row of cards is cropped away")

        // The owl is drawn upward from its feet, roughly a third of its height wide.
        let feet = mode.wonderingSpot
        let owlBox = CGRect(x: feet.x - RoomLayout.owlHeight / 3,
                            y: feet.y,
                            width: RoomLayout.owlHeight * 2 / 3,
                            height: RoomLayout.owlHeight)
        XCTAssertFalse(cards.intersects(owlBox), "the owl is standing on its own cards")
    }

    func testTheOwlGoesToTheBasketRatherThanStayingPut() {
        XCTAssertNotEqual(RoomLayout.approachPoint(for: .basket), RoomLayout.owlHome)
        XCTAssertNotEqual(RoomLayout.approachPoint(for: .basket),
                          RoomLayout.approachPoint(for: .window),
                          "the two halves must not be the same place in the room")
    }

    // MARK: The content behind it

    func testEveryQuestionTheOwlCanOfferHasAPictureAndAVoice() {
        guard let pack = try? ContentLoader.load() else {
            return XCTFail("no content pack")
        }
        XCTAssertFalse(pack.questions.isEmpty)

        for question in pack.questions {
            // The picture is the whole point of this corner: a child who cannot read has
            // nothing else to tell three cards apart by.
            XCTAssertNotNil(
                ContentLoader.illustrationURL(named: "question_\(question.id).png",
                                              language: pack.language),
                "question \(question.id) has no picture for its card")

            // And the owl has to be able to read the card out, because the picture alone
            // does not say which question it is.
            XCTAssertNotNil(
                ContentLoader.audioURL(for: SpokenText(id: question.id, text: question.text,
                                                       stem: "question_\(question.id)_prompt"),
                                       language: pack.language),
                "question \(question.id) has no clip of the owl reading it out")
        }
    }

    /// The invite is the only explanation a child gets of what the corner is.
    func testTheOwlHasSomethingToSayAtTheBasket() {
        guard let pack = try? ContentLoader.load() else {
            return XCTFail("no content pack")
        }
        let lines = pack.phrases[.wonderInvite] ?? []
        XCTAssertFalse(lines.isEmpty, "the owl arrives at the basket with nothing to say")

        for line in lines {
            XCTAssertNotNil(ContentLoader.audioURL(for: line, language: pack.language),
                            "phrase \(line.id) has no recording")
        }
    }

    // MARK: The mode

    func testTheModeStartsIdleAndCanBeginWithQuestions() {
        guard let pack = try? ContentLoader.load() else {
            return XCTFail("no content pack")
        }
        let scene = SKScene(size: RoomLayout.designSize)
        let owl = OwlNode(rig: WatercolourOwlRig(character: .owl))
        let mode = WonderMode(scene: scene, owl: owl, pack: pack, voice: OwlVoice(pack: pack))

        XCTAssertFalse(mode.isRunning)
        XCTAssertEqual(mode.phase, .idle)
        XCTAssertEqual(mode.canBegin, !pack.questions.isEmpty)
        XCTAssertNil(mode.againProp, "the basket offers another three by itself")

        // Leaving something that never started must not throw the room away.
        mode.leave()
        XCTAssertFalse(mode.isRunning)
        XCTAssertFalse(mode.handleTap(at: mode.cardsCentre),
                       "an idle mode must not swallow taps meant for the room")
    }
}
