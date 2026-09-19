import { IsLatitude, IsLongitude, IsOptional, IsString, Length, MaxLength } from 'class-validator';

export class SearchQueryDto {
  @IsString()
  @Length(1, 200)
  q: string;

  @IsOptional()
  @IsString()
  @MaxLength(50)
  near?: string; // "lat,lng" - optionaler Standort für Distanz-Bias
}

export interface SearchResult {
  label: string;
  lat: number;
  lng: number;
  type: 'ADDRESS' | 'POI';
 /** Postleitzahl, falls der Geocoder eine liefert (deutsche
   * PLZ-Suche: Nutzer tippen "80331" und erwarten Ortsergebnisse). */
  postcode?: string;
  /** Stadt/Gemeinde, falls erkannt - für die Sekundärzeile. */
  city?: string;
  /** Distanz zum `near`-Punkt in Metern, falls `near` übergeben wurde. */
  distanceMeters?: number;
}
