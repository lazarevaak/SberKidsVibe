//
//  CharacterRig.swift
//  MascotKit
//
//  Персонаж, описанный данными: набор картинок-деталей и character.json,
//  который говорит, где деталь крепится, вокруг какой точки вращается
//  и как двигается в каждом состоянии. Так художник может сделать любого
//  персонажа — зверька, машинку, ракету — без единой строчки кода.
//
//  Координаты — в точках, внутри рамки персонажа размером "size";
//  (0, 0) — левый верхний угол. Персонаж смотрит вправо (влево — зеркалится).
//

import SwiftUI
import UIKit

struct CharacterRig: Decodable {
    /// Рамка персонажа.
    var size: CGSize
    /// Точка опоры (между лап, под колёсами) — ей он стоит на карточках. По умолчанию — низ по центру.
    var foot: CGPoint?
    /// Где голова — над ней звёздочки, «z» и реплики. По умолчанию — верхняя четверть по центру.
    var head: CGPoint?
    /// Детали в порядке отрисовки: первая — самая дальняя.
    var parts: [RigPart]
    /// Свои анимации персонажа. Движения деталей — в part.motion под тем же именем.
    var animations: [String: RigAnimation]

    var footPoint: CGPoint { foot ?? CGPoint(x: size.width / 2, y: size.height) }
    var headPoint: CGPoint { head ?? CGPoint(x: size.width / 2, y: size.height * 0.25) }

    /// Все картинки персонажа — их нужно скачать до показа.
    var imageRefs: Set<String> {
        var refs = Set<String>()
        for part in parts {
            if let image = part.image { refs.insert(image) }
            part.images?.values.forEach { refs.insert($0) }
            part.motion?.values.compactMap(\.image).forEach { refs.insert($0) }
        }
        return refs
    }

    private enum CodingKeys: String, CodingKey { case size, foot, head, parts, animations }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        size = try c.decode(PointPair.self, forKey: .size).size
        foot = try c.decodeIfPresent(PointPair.self, forKey: .foot)?.point
        head = try c.decodeIfPresent(PointPair.self, forKey: .head)?.point
        parts = try c.decode([RigPart].self, forKey: .parts)
        animations = try c.decodeIfPresent([String: RigAnimation].self, forKey: .animations) ?? [:]
    }
}

/// Своя анимация: сколько длится и как двигается персонаж целиком.
/// Как двигаются отдельные детали — в их motion под именем анимации.
struct RigAnimation: Decodable {
    /// Длительность, секунды.
    var duration: Double = 2
    /// Вращение всего персонажа, градусов в секунду (360 — оборот за секунду).
    var spin: Double?
    /// Подпрыгивания всего персонажа: высота, pt.
    var bob: Double?
    /// Покачивание всего персонажа влево-вправо, pt.
    var sway: Double?
    /// Сколько подпрыгиваний или покачиваний в секунду.
    var freq: Double?
    /// Эмоция на время анимации: normal, happy, sleepy, dizzy, scared.
    var expression: String?
    /// Эффект вокруг: sparkles, stars, zzz.
    var effect: String?

    private enum CodingKeys: String, CodingKey { case duration, spin, bob, sway, freq, expression, effect }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        duration = min(max(try c.decodeIfPresent(Double.self, forKey: .duration) ?? 2, 0.3), 15)
        spin = try c.decodeIfPresent(Double.self, forKey: .spin)
        bob = try c.decodeIfPresent(Double.self, forKey: .bob)
        sway = try c.decodeIfPresent(Double.self, forKey: .sway)
        freq = try c.decodeIfPresent(Double.self, forKey: .freq)
        expression = try c.decodeIfPresent(String.self, forKey: .expression)
        effect = try c.decodeIfPresent(String.self, forKey: .effect)
    }
}

struct RigPart: Decodable {
    var id: String
    /// Картинка детали.
    var image: String?
    /// Картинки по эмоциям: normal, happy, sleepy, dizzy, scared и blink (моргание).
    var images: [String: String]?
    /// Размер детали.
    var size: CGSize
    /// Куда в рамке персонажа ставится точка вращения детали.
    var at: CGPoint
    /// Точка вращения внутри детали, доли 0…1. По умолчанию — центр.
    var pivot: CGPoint
    /// Вписать картинку в размер детали с сохранением пропорций (для подменяемых деталей вроде шапки).
    var fit: Bool
    /// Движения по состояниям: walk, idle, sit, sleep, wave, dance, celebrate,
    /// grabbed, air, dizzy, descend; "default" — для всех остальных.
    var motion: [String: RigMotion]?

    private enum CodingKeys: String, CodingKey { case id, image, images, size, at, pivot, fit, motion }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        image = try c.decodeIfPresent(String.self, forKey: .image)
        images = try c.decodeIfPresent([String: String].self, forKey: .images)
        size = try c.decode(PointPair.self, forKey: .size).size
        at = try c.decode(PointPair.self, forKey: .at).point
        pivot = try c.decodeIfPresent(PointPair.self, forKey: .pivot)?.point ?? CGPoint(x: 0.5, y: 0.5)
        fit = try c.decodeIfPresent(Bool.self, forKey: .fit) ?? false
        motion = try c.decodeIfPresent([String: RigMotion].self, forKey: .motion)
    }

    func motion(for state: String) -> RigMotion? {
        motion?[state] ?? motion?["default"]
    }
}

/// Движение детали в одном состоянии. Всё необязательно.
/// Колебания идут по «часам» состояния: при ходьбе и в полёте — по шагам, в покое — по времени.
struct RigMotion: Decodable {
    /// Постоянный поворот, градусы.
    var rotate: Double?
    /// Размах покачивания поворотом, градусы.
    var swing: Double?
    /// Размах подпрыгивания вверх-вниз, pt.
    var bob: Double?
    /// Размах покачивания влево-вправо, pt.
    var sway: Double?
    /// Частота колебаний относительно базовой (по умолчанию 1).
    var freq: Double?
    /// Сдвиг фазы колебаний, доля 0…1 — например, 0.5 для второй ноги.
    var phase: Double?
    /// Постоянное вращение, градусов на один шаг «часов» — для колёс.
    var spin: Double?
    /// Постоянный сдвиг, pt.
    var dx: Double?
    var dy: Double?
    var scale: Double?
    var hidden: Bool?
    /// Другая картинка детали в этом состоянии.
    var image: String?
}

/// [x, y] в JSON.
private struct PointPair: Decodable {
    let x: Double
    let y: Double
    var point: CGPoint { CGPoint(x: x, y: y) }
    var size: CGSize { CGSize(width: x, height: y) }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Double.self)
        y = try c.decode(Double.self)
    }
}

/// Персонаж, готовый к показу: описание + загруженные картинки.
struct LoadedCharacter {
    let rig: CharacterRig
    let images: [String: UIImage]

    /// Загружает character.json и все его картинки. Пути картинок — относительно character.json.
    /// Если не загрузилась хоть одна картинка — персонаж не показывается (лучше никакого, чем «с дырками»).
    static func load(_ ref: String, relativeTo base: URL?) async -> LoadedCharacter? {
        guard let url = URL(string: ref, relativeTo: base)?.absoluteURL,
              let data = await CDNContent.data(url.absoluteString, relativeTo: nil) else { return nil }
        let rig: CharacterRig
        do {
            rig = try JSONDecoder().decode(CharacterRig.self, from: data)
        } catch {
            MascotLog.content.error("Не удалось разобрать персонажа \(ref, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
        let files = await CDNContent.data(rig.imageRefs, relativeTo: url)
        var images: [String: UIImage] = [:]
        for imageRef in rig.imageRefs {
            guard let image = files[imageRef].flatMap({ UIImage(data: $0, scale: 3) }) else {
                MascotLog.content.error("У персонажа \(ref, privacy: .public) не загрузилась картинка \(imageRef, privacy: .public) — персонаж не показывается")
                return nil
            }
            // PNG распаковывается в фоне сейчас, а не на главном потоке в момент первого кадра —
            // иначе маскот «дёргается», когда появляется.
            images[imageRef] = await image.byPreparingForDisplay() ?? image
        }
        return LoadedCharacter(rig: rig, images: images)
    }
}
