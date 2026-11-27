-- Dokumente: Datei statt externer URL. Die Free-Tier-Instanz hat kein
-- Persistent Disk, deshalb liegen die Bytes (max. 8 MB) in der Datenbank.
ALTER TABLE "Document" ADD COLUMN IF NOT EXISTS "fileData" BYTEA;
ALTER TABLE "Document" ADD COLUMN IF NOT EXISTS "fileName" TEXT;
ALTER TABLE "Document" ADD COLUMN IF NOT EXISTS "hasFile" BOOLEAN NOT NULL DEFAULT false;
