// Wire-format types. Mirror the iOS Swift model so JSON shape stays
// identical end-to-end: Recording / AudioChunk encoded by Swift's
// auto-synthesized Codable produce exactly these fields.

export interface AudioChunk {
  index: number;
  listened: boolean;
}

export interface Recording {
  id: string;       // UUID string
  author: string;   // UUID string
  audioChunks: AudioChunk[];
}

export interface State {
  recordings: Recording[];
}

export type Mutation =
  | { type: "addRecording"; recording: Recording }
  | { type: "appendChunk"; recordingID: string; chunk: AudioChunk }
  | { type: "removeRecording"; recordingID: string }
  | { type: "markListened"; recordingID: string; chunkIndex: number; by?: string };
