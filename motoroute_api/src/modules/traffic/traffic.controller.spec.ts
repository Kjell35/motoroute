import { BadRequestException } from '@nestjs/common';
import { BoundingBoxParser } from './traffic.controller';

describe('BoundingBoxParser', () => {
  let parser: BoundingBoxParser;

  beforeEach(() => {
    parser = new BoundingBoxParser();
  });

  it('parses a valid bbox into numbers', () => {
    expect(parser.parse('11.0,47.0,12.5,48.5')).toEqual([11.0, 47.0, 12.5, 48.5]);
  });

  it('rejects a missing bbox instead of returning an empty result', () => {
    expect(() => parser.parse(undefined)).toThrow(BadRequestException);
  });

  it('rejects a bbox with too few coordinates', () => {
    expect(() => parser.parse('11.0,47.0,12.5')).toThrow(BadRequestException);
  });

  it('rejects a bbox containing non-numeric parts', () => {
    expect(() => parser.parse('11.0,abc,12.5,48.5')).toThrow(BadRequestException);
  });

  it('rejects an inverted bbox (min >= max)', () => {
    expect(() => parser.parse('12.5,47.0,11.0,48.5')).toThrow(BadRequestException);
    expect(() => parser.parse('11.0,48.5,12.5,47.0')).toThrow(BadRequestException);
  });
});
