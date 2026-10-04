"use client";
import { useState, type CSSProperties, type ReactNode } from "react";
import { Sparkles, Trophy, Layers, ArrowUpRight, Check } from "lucide-react";
export function Celebration() {
  return (
    <div className="celebration" aria-hidden="true">
      {Array.from({ length: 24 }, (_, i) => (
        <i
          key={i}
          style={
            {
              "--x": `${8 + ((i * 31) % 84)}%`,
              "--delay": `${(i % 6) * 60}ms`,
              "--drift": `${((i * 17) % 100) - 50}px`,
              "--turn": `${i * 37}deg`,
            } as CSSProperties
          }
        />
      ))}
    </div>
  );
}
export function RoundMoment({
  title,
  success = true,
}: {
  title: string;
  success?: boolean;
}) {
  return (
    <div
      className={`round-moment ${success ? "is-success" : ""}`}
      role="status"
    >
      {success && <Celebration />}
      <span className="moment-medallion">
        {success ? <Sparkles size={30} /> : <ArrowUpRight size={30} />}
      </span>
      <strong>{title}</strong>
    </div>
  );
}
export function ResultTrophy() {
  return (
    <div className="result-trophy" aria-hidden="true">
      <Trophy size={42} />
      <span />
      <span />
    </div>
  );
}
export function FlipQuestion({
  category,
  children,
}: {
  category: string;
  children: ReactNode;
}) {
  const [open, setOpen] = useState(false);
  return (
    <div className={`flip-question ${open ? "is-open" : ""}`}>
      <button
        className="card-back"
        aria-label="Reveal conversation card"
        onClick={() => setOpen(true)}
        disabled={open}
        tabIndex={open ? -1 : 0}
        aria-hidden={open}
      >
        <Layers size={38} />
        <span>{category}</span>
        <strong>A little closer.</strong>
        <small>
          Tap to turn the card <ArrowUpRight size={16} />
        </small>
      </button>
      <div className="card-front" aria-hidden={!open}>
        {open && children}
      </div>
    </div>
  );
}
export function ChoiceStamp({
  selected,
  option,
}: {
  selected: boolean;
  option: string;
}) {
  return (
    <span className="choice-stamp" aria-hidden="true">
      {selected ? <Check size={21} /> : option}
    </span>
  );
}
