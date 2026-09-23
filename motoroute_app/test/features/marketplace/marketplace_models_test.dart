import 'package:flutter_test/flutter_test.dart';

import 'package:motoroute_app/features/marketplace/marketplace_repository.dart';

/// Die App-Modelle spiegeln die Backend-Verträge - hier wird geprüft,
/// dass ein echtes Server-Antwort-Shape (marketplace_listings-Zeile mit
/// images-Join) korrekt geparst wird und die Review-Entscheidungen
/// korrekt durchschlagen.
void main() {
  group('MpListing.fromJson', () {
    test('parst eine echte listings-Zeile mit Bildern', () {
      final json = {
        'id': '11111111-1111-1111-1111-111111111111',
        'seller_id': '22222222-2222-2222-2222-222222222222',
        'title': 'BMW R1250 Auspuff',
        'description': 'Originales Endtopf',
        'price_cents': 45900,
        'condition': 'sehr_gut',
        'category': 'motorradteile',
        'subcategory': 'auspuff',
        'brand': 'BMW',
        'model': 'R1250 GS',
        'year': 2021,
        'location_label': 'München',
        'shipping': true,
        'status': 'active',
        'review_status': 'approved',
        'review_reason': 'Text und Fotos passen zu Fahrzeugteilen.',
        'created_at': '2026-09-23T10:00:00.000Z',
        'images': [
          {'storage_path': 'seller/listing/0.jpg', 'position': 0},
        ],
      };

      final listing = MpListing.fromJson(json);

      expect(listing.title, 'BMW R1250 Auspuff');
      expect(listing.priceCents, 45900);
      expect(listing.priceLabel, '459 €');
      expect(listing.condition, MpCondition.sehrGut);
      expect(listing.category, MpCategory.motorradteile);
      expect(listing.shipping, isTrue);
      expect(listing.reviewStatus, MpReviewStatus.approved);
      expect(listing.reviewStatus.isPubliclyVisible, isTrue);
      expect(listing.imageUrls, hasLength(1));
      expect(listing.imageUrls.first, contains('marketplace-photos'));
    });

    test('Parssing ohne Bilder und mit manual_review', () {
      final listing = MpListing.fromJson({
        'id': 'x',
        'title': 'Wie neu',
        'price_cents': 1000,
        'condition': 'gebraucht',
        'category': 'autoteile',
        'subcategory': 'motor',
        'location_label': 'Berlin',
        'shipping': false,
        'status': 'active',
        'review_status': 'manual_review',
        'created_at': '2026-09-23T10:00:00.000Z',
      });

      expect(listing.imageUrls, isEmpty);
      expect(listing.reviewStatus, MpReviewStatus.manualReview);
      expect(listing.reviewStatus.isPubliclyVisible, isFalse);
    });

    test('abgelehnt + Grund wird getragen (Punkt 6: Nutzer informieren)', () {
      final listing = MpListing.fromJson({
        'id': 'y',
        'title': 'Toaster',
        'price_cents': 500,
        'condition': 'gut',
        'category': 'sonstiges-falsch',
        'subcategory': 'sonstiges',
        'location_label': 'Köln',
        'review_status': 'rejected',
        'review_reason': 'Der Artikel ist kein Fahrzeugteil.',
      });

      expect(listing.reviewStatus, MpReviewStatus.rejected);
      expect(listing.reviewReason, contains('kein Fahrzeugteil'));
    });
  });

  group('MpCondition / MpCategory Mapping', () {
    test('Zustands-Enum spiegelt SQL-Check-Constraint', () {
      expect(MpCondition.neu.apiValue, 'neu');
      expect(MpCondition.sehrGut.apiValue, 'sehr_gut');
      expect(MpCondition.gebraucht.apiValue, 'gebraucht');
      expect(MpCondition.defekt.apiValue, 'defekt');
      expect(MpCondition.from('gut'), MpCondition.gut);
    });

    test('Kategorien decken genau die drei erlaubten Bereiche ab', () {
      expect(MpCategory.values, hasLength(3));
      expect(MpCategory.from('motorradteile'), MpCategory.motorradteile);
      expect(MpCategory.from('autoteile'), MpCategory.autoteile);
      expect(MpCategory.from('fahrradteile'), MpCategory.fahrradteile);
      // Unbekannt -> Motorrad (Default), nie Crash.
      expect(MpCategory.from('toaster'), MpCategory.motorradteile);
    });
  });
}
