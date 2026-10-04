export type Point = { x: number; y: number };
export type Stroke = {
  id: string;
  user_id: string;
  sequence: number;
  round: number;
  canvas_version: number;
  removed: boolean;
  stroke: {
    color: string;
    width: number;
    tool: "pen" | "eraser";
    points: Point[];
  };
};
