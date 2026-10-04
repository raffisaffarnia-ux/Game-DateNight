import type { ButtonHTMLAttributes, ReactNode } from "react";
import { LoaderCircle, Sparkles } from "lucide-react";
export function Button({
  children,
  secondary,
  className = "",
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { secondary?: boolean }) {
  return (
    <button
      className={`button ${secondary ? "secondary" : "primary"} ${className}`}
      {...props}
    >
      {children}
    </button>
  );
}
export function Card({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  return <div className={`card ${className}`}>{children}</div>;
}
export function Loading({ label = "Loading…" }: { label?: string }) {
  return (
    <div className="empty" role="status">
      <LoaderCircle className="spin" />
      <p>{label}</p>
    </div>
  );
}
export function EmptyState({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <div className="empty">
      <Sparkles size={32} />
      <h2>{title}</h2>
      {children}
    </div>
  );
}
