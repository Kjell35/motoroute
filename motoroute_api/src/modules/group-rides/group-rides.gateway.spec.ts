import { Test } from '@nestjs/testing';
import { GroupRidesGateway } from './group-rides.gateway';
import { ChatGateway } from '../chat/chat.gateway';
import { GroupRideEvent } from './group-rides.service';
import { BikerPoiRealtimeEvent } from '../biker-pois/biker-pois.realtime';
import type { Server, WebSocket } from 'ws';

/**
 * Ride-Radar-Verteilung: groupride.radar-Events (Positionen aus dem
 * Relais) dürfen NUR an Sockets im Ride-Raum gehen; die globalen
 * groupride.*-Status-Events bleiben positionsfrei. Getestet wird der
 * Gateway mit einem Fake-ChatGateway, dessen Socket-Verwaltung genau
 * diese Semantik abbildet (wie ChatGateway.broadcastToRide).
 */
describe('GroupRidesGateway - Ride-Radar-Verteilung', () => {
  let gateway: GroupRidesGateway;
  let chatGateway: {
    server?: Server;
    sockets: Map<WebSocket, { userId?: string; rideRooms: Set<string>; rooms: Set<string> }>;
    broadcastToRide: jest.Mock;
  };

  // Minimaler Fake-WebSocket (readyState, OPEN-Konstante + send).
  function fakeWs(open = true): WebSocket {
    return {
      readyState: open ? 1 : 3,
      OPEN: 1, // ws-WebSocket trägt die Konstante am Prototypen.
      send: jest.fn(),
    } as unknown as WebSocket;
  }

  beforeEach(async () => {
    const moduleRef = await Test.createTestingModule({
      providers: [
        GroupRidesGateway,
        {
          provide: ChatGateway,
          useValue: {
            broadcastToRide: jest.fn(),
          },
        },
      ],
    }).compile();
    gateway = moduleRef.get(GroupRidesGateway);
    chatGateway = moduleRef.get(ChatGateway);
  });

  it('groupride.radar geht NUR an Sockets im Ride-Raum der Route', () => {
    gateway.onRadarUpdate({
      routeId: 'route-1',
      members: [{ userId: 'u1', lat: 48.1, lng: 11.5, lastSeen: '2026-09-18T10:00:00Z' }],
    });

    expect(chatGateway.broadcastToRide).toHaveBeenCalledTimes(1);
    const [routeId, frame] = chatGateway.broadcastToRide.mock.calls[0];
    expect(routeId).toBe('route-1');
    expect(frame.event).toBe('groupride.radar');
    expect(frame.data.members).toHaveLength(1);
  });

  it('groupride.radar_leave geht NUR in den Ride-Raum', () => {
    gateway.onRadarLeave({ routeId: 'route-2', userId: 'u9' });

    const [routeId, frame] = chatGateway.broadcastToRide.mock.calls[0];
    expect(routeId).toBe('route-2');
    expect(frame.event).toBe('groupride.radar_leave');
    expect(frame.data).toEqual({ routeId: 'route-2', userId: 'u9' });
  });

  it('globale Status-Events bleiben positionsfrei (Positionsprivatsphäre)', () => {
    const sockets = new Map();
    const ws = fakeWs();
    sockets.set(ws, { userId: 'u1', rideRooms: new Set(), rooms: new Set() });
    chatGateway.sockets = sockets;
    chatGateway.server = { clients: [ws] } as unknown as Server;

    gateway.onHeartbeat({ routeId: 'route-1', userId: 'u1' });

    const sent = JSON.parse((ws.send as jest.Mock).mock.calls[0][0]);
    expect(sent.event).toBe(GroupRideEvent.POSITION_UPDATED);
    expect(sent.data).toEqual({ routeId: 'route-1', userId: 'u1' });
    expect(sent.data.lat).toBeUndefined();
    expect(JSON.stringify(sent.data)).not.toContain('lat');
  });
});
