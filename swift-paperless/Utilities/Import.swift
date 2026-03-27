//
//  Import.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 29.04.2024.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import PDFKit
import PhotosUI
import SwiftUI
import UIKit
import os

// @TODO: UIImage not available on macOS

enum DocumentImportError: LocalizedError {
  case photosReceivalFailed
  case nilTransferableImage
  case imageRenderFailed
  case pdfWriteFailed
  case pdfCreatePageFailed

  var errorDescription: String? {
    switch self {
    case .photosReceivalFailed, .nilTransferableImage, .imageRenderFailed:
      String(localized: .localizable(.photosReceivalFailed))
    case .pdfCreatePageFailed:
      String(localized: .localizable(.documentScanErrorCreatePageFailed))
    case .pdfWriteFailed:
      String(localized: .localizable(.documentScanErrorWriteFailed))
    }
  }
}

@MainActor
func createPDFFrom(photos: [PhotosPickerItem]) async throws -> URL {
  Logger.shared.debug("Creating PDF from \(photos.count) PhotosPickerItems")
  var images: [UIImage] = []
  for item in photos {
    guard let image = try await item.loadTransferable(type: Image.self) else {
      Logger.shared.error("loadTransferableImage returned nil instead of image")
      throw DocumentImportError.nilTransferableImage
    }

    let renderer = ImageRenderer(content: image)

    guard let uiImage = renderer.uiImage else {
      Logger.shared.error("Image renderer returned nil instead of UIImage")
      throw DocumentImportError.imageRenderFailed
    }
    images.append(uiImage)
  }

  return try createPDFFrom(images: images)
}

func formattedImportFilename(prefix: String = "Scan") -> String {
  let date = Date().formatted(
    .verbatim(
      "\(year: .extended())-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .oneBased)).\(minute: .twoDigits).\(second: .twoDigits)",
      timeZone: TimeZone.current,
      calendar: .current
    ))

  return "\(prefix) \(date)"
}

func applyFilter(_ filterMode: ScanFilterMode, to images: [UIImage]) -> [UIImage] {
  guard filterMode != .original else { return images }

  let context = CIContext()
  return images.map { image in
    guard let ciImage = CIImage(image: image) else { return image }

    let filtered: CIImage
    switch filterMode {
    case .original:
      return image
    case .grayscale:
      let filter = CIFilter.colorControls()
      filter.inputImage = ciImage
      filter.saturation = 0
      guard let output = filter.outputImage else { return image }
      filtered = output
    case .blackAndWhite:
      let filter = CIFilter.colorMonochrome()
      filter.inputImage = ciImage
      filter.color = CIColor(red: 0.5, green: 0.5, blue: 0.5)
      filter.intensity = 1.0
      guard let monoOutput = filter.outputImage else { return image }
      let threshold = CIFilter.colorControls()
      threshold.inputImage = monoOutput
      threshold.contrast = 4.0
      threshold.brightness = 0.1
      guard let output = threshold.outputImage else { return image }
      filtered = output
    }

    guard let cgImage = context.createCGImage(filtered, from: filtered.extent) else {
      return image
    }
    return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
  }
}

func createPDFFrom(images: [UIImage]) throws -> URL {
  let pdfDocument = PDFDocument()
  for i in 0..<images.count {
    if let pdfPage = PDFPage(image: images[i]) {
      pdfDocument.insert(pdfPage, at: i)
    } else {
      throw DocumentImportError.pdfCreatePageFailed
    }
  }

  let url = FileManager.default.temporaryDirectory
    .appending(component: formattedImportFilename())
    .appendingPathExtension("pdf")

  if pdfDocument.write(to: url) {
    return url
  } else {
    throw DocumentImportError.pdfWriteFailed
  }
}
