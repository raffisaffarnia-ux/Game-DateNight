import type { GameDefinition } from "@/lib/games";

const heart = "M0 4h4V0h8v4h4V0h8v4h4v12h-4v4h-4v4h-4v4h-4v-4H8v-4H4v-4H0Z";
function Heart({ x, y, color = "#e88383", scale = 1 }: { x: number; y: number; color?: string; scale?: number }) {
  return <path d={heart} transform={`translate(${x} ${y}) scale(${scale})`} fill={color} />;
}
function Candle({ x, y }: { x: number; y: number }) {
  return <g transform={`translate(${x} ${y})`}><path d="M-8 40h32v4H-8Z" fill="#8b6951" /><rect width="12" height="40" fill="#dfcba6" /><rect x="8" width="4" height="40" fill="#af9577" /><g className="px-flame"><path d="M4-20h4v8h4v12H0v-12h4Z" fill="#e6a75d" /><rect x="4" y="-8" width="4" height="8" fill="#ffe0a0" /></g></g>;
}
function Mug({ x, y, color }: { x: number; y: number; color: string }) {
  return <g transform={`translate(${x} ${y})`}><path d="M0 0h24v24H4v-4H0ZM24 4h8v12h-8v-4h4V8h-4Z" fill={color} /><rect x="4" y="4" width="16" height="4" fill="#342928" /><path className="px-steam" d="M8-8v-8h4v-8M16-8v-4h4v-12" fill="none" stroke="#bba58c" strokeWidth="4" /></g>;
}
function Person({ x, y, color }: { x: number; y: number; color: string }) {
  return <g transform={`translate(${x} ${y})`}><path d="M4 0h16v4h4v20H0V4h4Z" fill="#b77d60" /><path d="M4 4h16v16H4Z" fill="#e1b495" /><path d="M0 24h24v28H0Z" fill={color} /><path d="M0 52h8v12H0ZM16 52h8v12h-8Z" fill="#111c25" /></g>;
}
function Stars() {
  return <g className="px-stars" fill="#c4ae7a">{[[28,28],[64,56],[108,20],[312,24],[356,52],[376,104]].map(([x,y])=><path key={x} d={`M${x} ${y}h4v4h4v4h-4v4h-4v-4h-4v-4h4Z`} />)}</g>;
}
function Window() {
  return <g><rect x="128" y="24" width="144" height="104" fill="#3b4b54" /><rect x="136" y="32" width="128" height="88" fill="#15212e" /><path d="M196 32h8v88h-8ZM136 72h128v8H136Z" fill="#3b4b54" /><path d="M228 40h16v8h8v16h-24Z" fill="#c6b887" /><rect x="240" y="36" width="16" height="20" fill="#15212e" /></g>;
}

/** Shared code-native pixel scenes, matching the profile banners' stepped SVG artwork. */
export function PixelGameCover({ kind }: { kind: GameDefinition["art"] }) {
  return <div className={`game-art pixel-cover ${kind}`} aria-hidden="true">
    <svg className="pixel-scene" viewBox="0 0 400 220" shapeRendering="crispEdges" preserveAspectRatio="xMidYMid meet">
      <rect width="400" height="220" fill="#17232b" />
      <path d="M0 180h400v40H0Z" fill="#101a21" />
      <path d="M0 180h400v4H0Z" fill="#344049" />
      <Stars />

      {kind === "snake" && <>
        <rect x="60" y="36" width="280" height="152" fill="#263b35" />
        <rect x="68" y="44" width="264" height="136" fill="#142923" />
        {[84,116,148,180,212,244,276,308].map(x=><g key={x} fill="#274234">{[60,92,124,156].map(y=><rect key={y} x={x} y={y} width="4" height="4" />)}</g>)}
        <g className="px-snake"><path d="M92 144V76h64v32h32v16h-48V92h-32v52Z" fill="#73b69b" /><rect x="176" y="104" width="24" height="24" fill="#a1d2ad" /><rect x="192" y="108" width="4" height="4" fill="#132c29" /></g>
        <g className="px-snake-two"><path d="M304 76v68h-64v-32h-28V96h44v32h32V76Z" fill="#cb996a" /><rect x="204" y="92" width="24" height="24" fill="#e4b780" /><rect x="208" y="108" width="4" height="4" fill="#3c302a" /></g>
        <Heart x={190} y={144} scale={.5} color="#d87873" /><Heart x={206} y={58} scale={.5} color="#d87873" />
      </>}

      {kind === "cards" && <>
        <Window />
        <rect x="64" y="132" width="272" height="12" fill="#967457" /><path d="M80 144h12v52H80ZM308 144h12v52h-12Z" fill="#654c40" />
        <Candle x={100} y={88} /><Candle x={292} y={88} />
        <Mug x={140} y={108} color="#7eaaa0" /><Mug x={232} y={108} color="#bd817d" />
        <g className="px-float"><path d="M156 40h40v24h-12v12h-8V64h-20Z" fill="#8bb2ae" /><path d="M208 44h40v24h-20v12h-8V68h-12Z" fill="#d1a389" /><rect x="164" y="48" width="24" height="4" fill="#3a5555" /><rect x="216" y="52" width="24" height="4" fill="#76564a" /></g>
      </>}

      {kind === "orbits" && <>
        <rect x="64" y="44" width="116" height="124" fill="#35464e" /><rect x="72" y="52" width="100" height="108" fill="#21353c" />
        <rect x="220" y="44" width="116" height="124" fill="#4e4443" /><rect x="228" y="52" width="100" height="108" fill="#342e31" />
        <path className="px-orbit" d="M104 72h32v8h8v32h-8v8h-32v-8h-8V80h8Z" fill="#cfb571" /><path d="M280 72h24v8h8v32h-8v8h-24v-8h-8V80h8Z" fill="#b0c9cf" /><path d="M292 68h20v40h-20v-8h-8V80h8Z" fill="#342e31" />
        <path d="M112 140h16v4h-16ZM272 140h16v4h-16Z" fill="#d7c9a9" />
        <g className="px-float"><Heart x={186} y={106} color="#dc8b80" /></g>
      </>}

      {kind === "tiles" && <>
        <path d="M76 48h100v124H76ZM224 48h100v124H224Z" fill="#49606a" /><path d="M84 56h84v108H84ZM232 56h84v108H232Z" fill="#233743" />
        <Person x={114} y={88} color="#7eaaa0" /><Person x={260} y={88} color="#c5917b" />
        <g className="px-float"><path d="M188 44h24v8h8v16h-8v8h-8v8h-8V68h12V56h-20Z" fill="#dac28c" /><rect x="196" y="92" width="8" height="8" fill="#dac28c" /></g>
        <Heart x={186} y={144} scale={1} />
      </>}

      {kind === "drawing" && <>
        <Window />
        <path d="M188 44h12v136h-12ZM168 164h12l-8 36h-12ZM216 164h12l12 36h-12Z" fill="#967151" />
        <rect x="140" y="60" width="116" height="104" fill="#a18460" /><rect x="148" y="68" width="100" height="88" fill="#dfd1ad" />
        <Heart x={168} y={88} scale={2} color="#b85e60" /><rect x="204" y="120" width="16" height="8" fill="#d48878" />
        <rect x="76" y="144" width="36" height="40" fill="#6c9894" /><path d="M84 148V100h8v48ZM100 148v-36h8v36Z" fill="#b89d71" /><rect x="84" y="92" width="8" height="16" fill="#c46b68" />
        <rect x="288" y="156" width="28" height="28" fill="#bf9761" /><rect x="316" y="160" width="24" height="24" fill="#9b6e73" /><g className="px-stars"><rect x="276" y="80" width="8" height="8" fill="#ddb56f" /><rect x="116" y="108" width="8" height="8" fill="#d58984" /></g>
      </>}

      {kind === "daily" && <>
        <rect x="64" y="36" width="120" height="104" fill="#5a665d" /><rect x="72" y="44" width="104" height="88" fill="#263e42" /><g className="px-float"><path d="M108 72h32v8h8v24h-8v8h-32v-8h-8V80h8Z" fill="#d6b06d" /></g><path d="M72 116h104v16H72Z" fill="#476951" />
        <rect x="216" y="48" width="104" height="100" fill="#c3b59b" /><rect x="216" y="48" width="104" height="24" fill="#a55956" /><path d="M236 40h8v16h-8ZM292 40h8v16h-8Z" fill="#e0c79e" />
        <g fill="#9c8b75">{[232,256,280].map(x=><rect key={x} x={x} y="84" width="12" height="8" />)}</g><Heart x={254} y={102} scale={.85} color="#a55956" />
        <Mug x={116} y={156} color="#7eaaa0" /><Mug x={260} y={156} color="#c58f77" />
      </>}

      {kind === "bomb" && <>
        <path d="M96 68h208v12h12v88H84V80h12Z" fill="#48565b" /><rect x="96" y="80" width="208" height="76" fill="#25333b" />
        <rect x="116" y="92" width="92" height="40" fill="#111e25" /><path d="M128 100h20v8h-12v8h12v8h-20ZM160 100h8v24h-8ZM180 100h16v8h-8v8h8v8h-16Z" fill="#dda56e" />
        <path d="M228 92h56v12h-40v16h40v12h-56Z" fill="#b86b66" /><path d="M228 144h56v-8h-44v-24h-12Z" fill="#76a9a4" />
        <path d="M164 68V44h48V32h36" fill="none" stroke="#bd9d70" strokeWidth="8" /><g className="px-flame"><path d="M244 20h8v8h8v8h-8v8h-8v-8h-8v-8h8Z" fill="#edbe75" /></g>
        <Person x={48} y={124} color="#77a79d" /><Person x={332} y={124} color="#bd8b77" />
      </>}

      {kind === "moral" && <>
        <path d="M192 56h16v112h28v12h-72v-12h28Z" fill="#c6a36d" /><path d="M104 76h192v8H104Z" fill="#d4b57b" />
        <g className="px-balance"><path d="M120 84v44M280 84v44" stroke="#9d865f" strokeWidth="4" /><path d="M84 128h72v8h-8v12H92v-12h-8ZM244 128h72v8h-8v12h-56v-12h-8Z" fill="#719b9e" /><Heart x={106} y={100} scale={.85} color="#d78b80" /><path d="M268 100h24v24h-24Z" fill="#dac38d" /><rect x="276" y="108" width="8" height="8" fill="#a18d64" /></g>
        <path d="M184 48h32v8h-32Z" fill="#ecd49e" />
      </>}

      {kind === "rank" && <>
        <path d="M60 128h84v60H60Z" fill="#4c7380" /><path d="M156 96h88v92h-88Z" fill="#a5844e" /><path d="M256 144h84v44h-84Z" fill="#745453" />
        <path d="M60 128h84v8H60ZM156 96h88v8h-88ZM256 144h84v8h-84Z" fill="#c7b494" />
        <Heart x={86} y={88} color="#83b5ac" /><g className="px-float"><Heart x={178} y={42} scale={1.5} color="#e2b979" /></g><Heart x={284} y={104} color="#d58d85" />
        <path d="M96 152h12v16H96ZM192 120h12v20h-12ZM292 164h12v12h-12Z" fill="#e7d4ae" />
      </>}
    </svg>
  </div>;
}

