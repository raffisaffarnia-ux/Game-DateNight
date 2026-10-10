const heart = "M0 4h4V0h8v4h4V0h8v4h4v12h-4v4h-4v4h-4v4h-4v-4H8v-4H4v-4H0Z";
function Heart({
  x,
  y,
  size = 1,
  color = "#fb9caf",
}: {
  x: number;
  y: number;
  size?: number;
  color?: string;
}) {
  return (
    <path
      d={heart}
      transform={`translate(${x} ${y}) scale(${size})`}
      fill={color}
    />
  );
}
function Candle({ x, y }: { x: number; y: number }) {
  return (
    <g transform={`translate(${x} ${y})`}>
      <rect x="-12" y="47" width="36" height="6" fill="#dba674" />
      <rect width="12" height="48" fill="#fff0d2" />
      <rect x="8" width="4" height="48" fill="#ebc8a7" />
      <path d="M4-22h4v6h4v12H0v-8h4Z" fill="#ffc76e" />
      <rect x="4" y="-10" width="4" height="8" fill="#fff3ac" />
    </g>
  );
}
function Couple({ x, y }: { x: number; y: number }) {
  return (
    <g transform={`translate(${x} ${y})`}>
      <path d="M0 0h16v16H0ZM24 0h16v16H24Z" fill="#ffd4bd" />
      <path d="M-4 16h24v28H-4Z" fill="#cc9ee8" />
      <path d="M20 16h24v28H20Z" fill="#99c9c2" />
      <path d="M0-4h16v8H0ZM24-4h16v8H24Z" fill="#403450" />
    </g>
  );
}
export function DateScene({ id }: { id: string }) {
  if (
    ![
      "candlelight",
      "picnic",
      "rooftop",
      "stargazing",
      "love-letter",
      "movie-night",
    ].includes(id)
  )
    return null;
  return (
    <g>
      {id === "candlelight" && (
        <>
          <rect width="400" height="140" fill="#382436" />
          <rect x="16" y="14" width="368" height="6" fill="#794052" />
          {[34, 94, 154, 214, 274, 334].map((x) => (
            <Heart key={x} x={x} y={30} size={0.45} color="#dd8e9e" />
          ))}
          <path d="M50 113h300v27H50Z" fill="#c47889" />
          <path d="M50 113h300v6H50Z" fill="#f2b3ae" />
          <Candle x={116} y={64} />
          <Candle x={275} y={64} />
          <ellipse cx="200" cy="112" rx="36" ry="7" fill="#f8d5bc" />
          <Heart x={188} y={78} size={0.85} />
        </>
      )}
      {id === "picnic" && (
        <>
          <rect width="400" height="140" fill="#c3dcb4" />
          <path
            d="M0 80h50V68h58v12h68V64h66v16h78V60h80v80H0Z"
            fill="#6f9c7c"
          />
          <rect x="116" y="93" width="184" height="47" fill="#efadae" />
          {[124, 160, 196, 232, 268].map((x) => (
            <rect key={x} x={x} y="93" width="12" height="47" fill="#ffe4d0" />
          ))}
          <rect x="116" y="107" width="184" height="8" fill="#ffe4d0" />
          <Couple x={175} y={65} />
          <rect x="260" y="80" width="28" height="24" fill="#ae7951" />
          <Heart x={192} y={26} size={0.65} color="#d36d8c" />
        </>
      )}
      {id === "rooftop" && (
        <>
          <rect width="400" height="140" fill="#61486f" />
          <path
            d="M0 70h40V50h28v52h40V78h35v62H0ZM260 100h35V64h42V42h40v32h23v66H260Z"
            fill="#392c50"
          />
          {[18, 50, 302, 344, 368].map((x) => (
            <g key={x}>
              <rect x={x} y="82" width="7" height="8" fill="#edba99" />
              <rect x={x} y="102" width="7" height="8" fill="#edba99" />
            </g>
          ))}
          <rect x="111" y="121" width="176" height="19" fill="#25293e" />
          <Couple x={180} y={77} />
          <path d="M65 18h265v3H65Z" fill="#f2ceab" />
          {[80, 120, 160, 200, 240, 280, 320].map((x) => (
            <rect key={x} x={x} y="22" width="5" height="7" fill="#ffe4b9" />
          ))}
          <Heart x={190} y={40} size={0.6} />
        </>
      )}
      {id === "stargazing" && (
        <>
          <rect width="400" height="140" fill="#252c51" />
          {[28, 64, 106, 153, 239, 287, 327, 365].map((x, i) => (
            <path
              key={x}
              d={`M${x} ${18 + (i % 3) * 18}h4v-4h4v4h4v4h-4v4h-4v-4h-4Z`}
              fill="#f1dba9"
            />
          ))}
          <path d="M286 8h20v8h8v24h-8v8h-24v-8h-8V16h12Z" fill="#efe1bd" />
          <path d="M300 8h16v32h-16v-8h-8V16h8Z" fill="#252c51" />
          <path
            d="M0 130h44v-8h56v-8h68v-8h64v8h68v8h56v8h44v10H0Z"
            fill="#635b83"
          />
          <Couple x={181} y={70} />
          <Heart x={188} y={29} size={0.65} color="#d6aff0" />
        </>
      )}
      {id === "love-letter" && (
        <>
          <rect width="400" height="140" fill="#c996ae" />
          {[20, 85, 303, 355].map((x, i) => (
            <Heart
              key={x}
              x={x}
              y={22 + (i % 2) * 72}
              size={0.6}
              color="#f6cad0"
            />
          ))}
          <path d="M134 38h132v82H134Z" fill="#f9e3c7" />
          <path
            d="M134 38h12v10h12v10h12v10h12v10h36V68h12V58h12V48h12V38h12v8h-12v12h-12v12h-12v12h-12v8h-36v-8h-12V70h-12V58h-12V46h-12Z"
            fill="#d6b09a"
          />
          <Heart x={186} y={68} size={1} color="#d66f90" />
        </>
      )}
      {id === "movie-night" && (
        <>
          <rect width="400" height="140" fill="#30283d" />
          <rect x="106" y="8" width="188" height="82" fill="#80657f" />
          <rect x="114" y="16" width="172" height="66" fill="#f1c3c8" />
          <Heart x={185} y={33} size={1.1} color="#c56286" />
          <rect x="110" y="103" width="180" height="37" fill="#865369" />
          <Couple x={178} y={82} />
          <path d="M70 92h24v36H70Z" fill="#f9d3ac" />
          <path d="M74 96h4v28h-4ZM84 96h4v28h-4Z" fill="#db6d83" />
          <path d="M66 86h8v-6h8v6h8v-6h8v14H66Z" fill="#ffe7b1" />
        </>
      )}
    </g>
  );
}
