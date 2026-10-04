"use client";
import { useEffect, useRef, type PointerEvent } from "react";
import type { Stroke, Point } from "./types";
export function DrawingCanvas({
  strokes,
  userId,
  round,
  version,
  color,
  width,
  tool,
  disabled,
  preview,
  commit,
}: {
  strokes: Stroke[];
  userId: string;
  round: number;
  version: number;
  color: string;
  width: number;
  tool: "pen" | "eraser";
  disabled: boolean;
  preview: (stroke: Stroke) => void;
  commit: (stroke: Stroke) => void;
}) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const current = useRef<Stroke | null>(null);
  const sentAt = useRef(0);
  const latest = useRef(strokes);
  latest.current = strokes;
  useEffect(() => {
    current.current = null;
  }, [round, version, disabled]);
  useEffect(() => {
    const el = canvas.current;
    if (!el) return;
    const render = () => {
      const rect = el.getBoundingClientRect();
      const dpr = window.devicePixelRatio || 1;
      el.width = rect.width * dpr;
      el.height = rect.height * dpr;
      const ctx = el.getContext("2d");
      if (!ctx) return;
      ctx.scale(el.width, el.height);
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      for (const { stroke: s } of latest.current) {
        if (!s.points.length) continue;
        ctx.globalCompositeOperation =
          s.tool === "eraser" ? "destination-out" : "source-over";
        ctx.strokeStyle = s.color;
        ctx.fillStyle = s.color;
        ctx.lineWidth = s.width;
        ctx.beginPath();
        ctx.moveTo(s.points[0].x, s.points[0].y);
        for (const p of s.points.slice(1)) ctx.lineTo(p.x, p.y);
        if (s.points.length === 1) {
          ctx.arc(s.points[0].x, s.points[0].y, s.width / 2, 0, Math.PI * 2);
          ctx.fill();
        } else ctx.stroke();
      }
    };
    render();
    const observer = new ResizeObserver(render);
    observer.observe(el);
    return () => observer.disconnect();
  }, [strokes]);
  const point = (e: PointerEvent<HTMLCanvasElement>): Point => {
    const r = e.currentTarget.getBoundingClientRect();
    return {
      x: Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)),
      y: Math.max(0, Math.min(1, (e.clientY - r.top) / r.height)),
    };
  };
  function end() {
    const s = current.current;
    if (!s) return;
    current.current = null;
    preview(s);
    commit(s);
  }
  return (
    <canvas
      ref={canvas}
      className="drawing-canvas"
      aria-label={
        disabled
          ? "Shared drawing canvas, view only"
          : "Shared canvas. Draw with a mouse, touch or stylus."
      }
      role="img"
      onPointerDown={(e) => {
        if (disabled || e.button !== 0 || !e.isPrimary || current.current)
          return;
        e.preventDefault();
        e.currentTarget.setPointerCapture(e.pointerId);
        current.current = {
          id: crypto.randomUUID(),
          user_id: userId,
          sequence: 0,
          round,
          canvas_version: version,
          removed: false,
          stroke: { color, width, tool, points: [point(e)] },
        };
        preview(current.current);
      }}
      onPointerMove={(e) => {
        if (!current.current || disabled || !e.isPrimary) return;
        e.preventDefault();
        const s = current.current;
        if (s.stroke.points.length >= 512) {
          end();
          return;
        }
        s.stroke.points.push(point(e));
        if (performance.now() - sentAt.current > 60) {
          preview({
            ...s,
            stroke: { ...s.stroke, points: [...s.stroke.points] },
          });
          sentAt.current = performance.now();
        }
      }}
      onPointerUp={(e) => {
        if (e.isPrimary) end();
      }}
      onPointerCancel={(e) => {
        if (e.isPrimary) end();
      }}
      onLostPointerCapture={(e) => {
        if (e.isPrimary) end();
      }}
    />
  );
}
