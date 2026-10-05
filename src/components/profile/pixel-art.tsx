import type { CSSProperties } from "react";
const sprites: Record<string, string[]> = {
  cat: [
    "..11......11..",
    "..121....121..",
    "..1221111221..",
    "..1222222221..",
    ".122222222221.",
    ".122332233221.",
    ".122332233221.",
    ".122224422221.",
    "..1224444221..",
    "...12222221...",
    "....111111....",
  ],
  fox: [
    ".11........11.",
    ".121......121.",
    ".122111111221.",
    ".122222222221.",
    "..1222222221..",
    "..1242242241..",
    "...13333331...",
    "....133331....",
    ".....1441.....",
    "......11......",
  ],
  frog: [
    "..111....111..",
    ".12221..12221.",
    ".12321..12321.",
    ".122211112221.",
    ".122222222221.",
    "12222222222221",
    "12242222224221",
    ".122444444221.",
    "..1222222221..",
    "...11111111...",
  ],
  ghost: [
    "....111111....",
    "...12222221...",
    "..1222222221..",
    ".122222222221.",
    ".122332233221.",
    ".122332233221.",
    ".122222222221.",
    ".122224422221.",
    ".122222222221.",
    ".122122122121.",
    "..11.11.11.1..",
  ],
  robot: [
    "......11......",
    "......44......",
    "...11111111...",
    "..1222222221..",
    "..1233223321..",
    "11223322332211",
    "12222222222221",
    "11224444442211",
    "..1222222221..",
    "...11111111...",
  ],
  bear: [
    "..111....111..",
    ".12221..12221.",
    ".122211112221.",
    "..1222222221..",
    ".122332233221.",
    ".122222222221.",
    ".122244442221.",
    "..1224334221..",
    "...12244221...",
    "....111111....",
  ],
  heart: [
    ".11..11.",
    "12211221",
    "12222221",
    ".122221.",
    "..1221..",
    "...11...",
  ],
  star: [
    "...11...",
    "..1221..",
    "11122111",
    "12222221",
    ".122221.",
    "12211221",
    "11....11",
  ],
  crown: [
    "11.11.11",
    "12122121",
    "12222221",
    ".122221.",
    ".144441.",
    ".111111.",
  ],
  diamond: [
    "..1111..",
    ".122221.",
    "12333321",
    ".123321.",
    "..1221..",
    "...11...",
  ],
};
const colors: Record<string, string[]> = {
  cat: ["#372a62", "#bda5ff", "#29243e", "#ff99bb"],
  fox: ["#673353", "#ffac6d", "#ffe1b8", "#382345"],
  frog: ["#255346", "#8edc9c", "#203b3a", "#ed93ad"],
  ghost: ["#625486", "#eee8ff", "#4c4267", "#ffadd0"],
  robot: ["#29497a", "#91d9ee", "#243455", "#ffa7cf"],
  bear: ["#70423d", "#dca579", "#362b36", "#f6d5ac"],
  heart: ["#973a62", "#ff91b2", "#fff", "#ffdbed"],
  star: ["#926226", "#ffe089", "#fff", "#ffbd6b"],
  crown: ["#95632b", "#ffe29a", "#fff", "#e396ff"],
  diamond: ["#5069a1", "#b1e9ff", "#e9faff", "#fff"],
};
export function PixelArt({
  id = "cat",
  className = "",
}: {
  id?: string;
  className?: string;
}) {
  const rows = sprites[id] || sprites.cat,
    palette = colors[id] || colors.cat;
  return (
    <svg
      className={`pixel-art ${className}`}
      viewBox={`-2 -2 ${rows[0].length + 4} ${rows.length + 4}`}
      role="img"
      aria-label={id}
      shapeRendering="crispEdges"
    >
      {rows.flatMap((row, y) =>
        [...row].map((v, x) =>
          v === "." ? null : (
            <rect
              key={`${x}-${y}`}
              x={x}
              y={y}
              width="1"
              height="1"
              fill={palette[Number(v) - 1]}
            />
          ),
        ),
      )}
    </svg>
  );
}
export function PixelBanner({
  id = "dusk",
  children,
  className = "",
}: {
  id?: string;
  children?: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={`pixel-banner banner-${id} ${className}`}>
      <svg
        viewBox="0 0 400 140"
        preserveAspectRatio="xMidYMid slice"
        aria-hidden="true"
        shapeRendering="crispEdges"
      >
        <circle cx="310" cy="42" r="24" fill="var(--pixel-sun)" />
        <path
          d="M0 110h25V94h25v16h25V82h25V66h25v20h25v24h25V94h25v16h25V80h25v14h25v16h25V74h25V58h25v26h25v26h25v30H0Z"
          fill="var(--pixel-far)"
        />
        <path
          d="M0 124h40v-12h28v12h52v-20h24v20h36v-8h28v8h56v-20h32v12h36v8h68v16H0Z"
          fill="var(--pixel-near)"
        />
        {[20, 65, 115, 160, 210, 265, 360].map((x, i) => (
          <path
            key={x}
            d={`M${x} ${18 + (i % 3) * 17}h4v-4h4v4h4v4h-4v4h-4v-4h-4Z`}
            fill="var(--pixel-star)"
          />
        ))}
      </svg>
      {children}
    </div>
  );
}
export function Coin({ style }: { style?: CSSProperties }) {
  return (
    <span className="pixel-coin" style={style} aria-hidden="true">
      ✦
    </span>
  );
}
