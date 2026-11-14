import { useId } from "react";

export function RoomScene({ picks }: { picks: number[] }) {
  const [style, bed, palette, light, extra] = picks;
  const colors = [
    ["#dac8aa", "#94765b", "#f5ebdb"],
    ["#b9bec1", "#45484c", "#efeee8"],
    ["#d4bddb", "#a67e91", "#eee0dc"],
    ["#b9be9a", "#6d7962", "#e4dbc0"],
  ][palette ?? 0];
  return (
    <svg
      viewBox="0 0 300 220"
      role="img"
      aria-label="Dein gestaltetes Schlafzimmer"
    >
      <path d="M18 25H282V190H18Z" fill={colors[0]} />
      <path d="M18 158H282V206H18Z" fill={colors[1]} />
      <path
        d="M18 25L48 42V158L18 206M282 25L252 42V158L282 206"
        fill="#222"
        opacity=".1"
      />
      {style === 0 && (
        <path
          d="M48 43H251M48 74H251M48 105H251M48 136H251"
          stroke="#fff"
          opacity=".3"
        />
      )}
      {style === 1 && (
        <path
          d="M62 28V155M90 28V155M118 28V155M146 28V155M174 28V155M202 28V155M230 28V155"
          stroke={colors[1]}
          opacity=".2"
          strokeWidth="8"
        />
      )}
      {style === 3 && (
        <g fill="none" stroke="#f2d59b" strokeWidth="2">
          <rect x="55" y="39" width="82" height="100" />
          <rect x="155" y="39" width="82" height="100" />
        </g>
      )}
      <ellipse
        cx="150"
        cy="180"
        rx="91"
        ry="22"
        fill={colors[2]}
        opacity=".5"
      />
      <rect
        x="96"
        y={bed === 3 ? 127 : 101}
        width="108"
        height="58"
        rx={bed === 1 ? 16 : 3}
        fill={colors[1]}
      />
      <path
        d={bed === 3 ? "M91 145H209L225 183H75Z" : "M91 124H209L225 174H75Z"}
        fill={colors[2]}
      />
      <path
        d={bed === 3 ? "M75 183H225V190H75Z" : "M75 174H225V188H75Z"}
        fill={colors[1]}
      />
      <path d="M93 136H207L216 162H84Z" fill={colors[0]} />
      <rect
        x="100"
        y={bed === 3 ? 146 : 126}
        width="44"
        height="13"
        rx="5"
        fill="#fff4df"
      />
      <rect
        x="157"
        y={bed === 3 ? 146 : 126}
        width="44"
        height="13"
        rx="5"
        fill="#fff4df"
      />
      {bed === 2 && (
        <g fill="none" stroke="#684c43" strokeWidth="3">
          <path d="M77 187V65H222V187M77 65L99 49H204L222 65" />
          <path d="M99 49V123M204 49V123" opacity=".6" />
        </g>
      )}
      {light === 0 && <path d="M49 43H250" stroke="#d9b8f3" strokeWidth="5" />}
      {light === 1 && (
        <g fill="#ffe2a2">
          <path d="M59 112H72L77 135H54Z" />
          <rect x="64" y="135" width="3" height="24" />
        </g>
      )}
      {light === 2 && (
        <g>
          <path d="M150 25V57" stroke="#493f39" strokeWidth="2" />
          <path d="M130 72Q130 53 150 53Q170 53 170 72Z" fill="#e9af66" />
        </g>
      )}
      {light === 3 && (
        <g fill="#ffe6b0">
          <path d="M51 55Q150 97 249 55" fill="none" stroke="#887858" />
          {[65, 90, 115, 140, 165, 190, 215, 240].map((x, i) => (
            <circle
              key={x}
              cx={x}
              cy={60 + Math.sin((i / 7) * Math.PI) * 18}
              r="3"
            />
          ))}
        </g>
      )}
      {extra === 0 && (
        <g>
          <rect x="224" y="69" width="29" height="79" fill="#708f8e" />
          <path d="M225 112H253M237 70V148" stroke="#e5d7b7" strokeWidth="3" />
          <circle cx="245" cy="83" r="7" fill="#f7d49c" />
        </g>
      )}
      {extra === 1 && (
        <g>
          <path d="M31 150H76V155H31Z" fill="#4b4544" />
          <rect x="38" y="119" width="30" height="23" rx="2" fill="#3f4351" />
          <rect x="41" y="122" width="24" height="16" fill="#aca8d3" />
          <path
            d="M53 141V150M36 155V176M71 155V176"
            stroke="#4b4544"
            strokeWidth="3"
          />
        </g>
      )}
      {extra === 2 && (
        <g>
          <rect x="224" y="132" width="32" height="38" rx="12" fill="#8f665c" />
          <path d="M222 169H257V177H222" fill="#b58c6d" />
          <path d="M228 176V184M251 176V184" stroke="#4b4544" strokeWidth="3" />
        </g>
      )}
      {extra === 3 && (
        <g>
          <rect x="29" y="83" width="43" height="82" fill="#896b58" />
          <path d="M50 85V162" stroke="#ddc1a0" />
          <circle cx="45" cy="129" r="2" fill="#f5d898" />
        </g>
      )}
      <path
        d="M265 172V141M265 152Q245 139 255 134Q268 139 265 152M265 147Q279 129 281 140Q276 148 265 147"
        fill="#5e7962"
        stroke="#5e7962"
        strokeWidth="2"
      />
      <path d="M257 166H275L272 183H260Z" fill="#a85e4c" />
    </svg>
  );
}
export function PizzaScene({ picks }: { picks: number[] }) {
  const [dough, sauce, cheese, topping, extra] = picks;
  const id = useId();
  return (
    <svg viewBox="0 0 300 220" role="img" aria-label="Deine belegte Pizza">
      <ellipse cx="150" cy="195" rx="88" ry="9" fill="#40382a" opacity=".2" />
      <circle cx="150" cy="109" r="89" fill="#f5e6c5" />
      <circle
        cx="150"
        cy="109"
        r="80"
        fill={dough === 2 ? "#ad7743" : "#d99b52"}
        stroke="#ae703b"
        strokeWidth="2"
      />
      <circle
        cx="150"
        cy="109"
        r={dough === 1 ? 65 : 71}
        fill={["#b44d37", "#6e8848", "#eddfb5"][sauce ?? 0]}
      />
      <defs>
        <clipPath id={id}>
          <circle cx="150" cy="109" r="64" />
        </clipPath>
      </defs>
      <g clipPath={"url(#" + id + ")"}>
        {[0, 1, 2, 3, 4, 5, 6, 7].map((i) => {
          const angle = i * 2.4,
            x = 150 + Math.cos(angle) * (25 + i * 4),
            y = 109 + Math.sin(angle) * (25 + i * 4);
          return (
            <g
              key={i}
              transform={
                "translate(" + x + " " + y + ") rotate(" + i * 37 + ")"
              }
            >
              <ellipse
                rx="16"
                ry="11"
                fill={cheese === 1 ? "#cad1b2" : "#f8e9b6"}
              />
              {cheese === 1 && (
                <path
                  d="M-9 -3L2 2L7 -5"
                  stroke="#719186"
                  strokeWidth="2"
                  fill="none"
                />
              )}
              {topping === 0 ? (
                <g fill="#baa58a" stroke="#745e4b">
                  <path d="M-7 1Q-12 -12 0 -12Q12 -12 7 1Z" />
                  <path d="M-2 1V8H2V1" />
                </g>
              ) : topping === 1 ? (
                <circle r="9" fill="#ad4c3c" stroke="#db9470" strokeWidth="2" />
              ) : topping === 2 ? (
                <path
                  d="M0 10Q-15 -5 -7 -11L0 -5L7 -11Q15 -5 0 10"
                  fill="#7e8d53"
                />
              ) : null}
              {extra === 0 ? (
                <ellipse
                  cx="12"
                  cy="8"
                  rx="5"
                  ry="10"
                  fill="#5f8948"
                  transform="rotate(30)"
                />
              ) : extra === 1 ? (
                <circle cx="13" cy="8" r="2" fill="#c53b29" />
              ) : extra === 2 ? (
                <path
                  d="M9 16Q6 0 15 -4M8 8L1 4M11 3L18 0"
                  fill="none"
                  stroke="#4a783f"
                  strokeWidth="2"
                />
              ) : null}
            </g>
          );
        })}
      </g>
    </svg>
  );
}
export function CarScene({ picks }: { picks: number[] }) {
  const [type, color, wheels, inside, extra] = picks;
  const body = ["#ac4a52", "#91a28b", "#53555e"][color ?? 0];
  return (
    <svg viewBox="0 0 300 220" role="img" aria-label="Dein gestaltetes Auto">
      <path d="M18 169H282" stroke="#796b61" />
      <ellipse
        cx="150"
        cy="171"
        rx="123"
        ry="12"
        fill="#3e3535"
        opacity=".18"
      />
      <path
        d={
          type === 1
            ? "M42 134L57 88H208L246 129L273 138V157H28V139Z"
            : type === 0
              ? "M32 139L71 129H188L231 130L270 142V158H30Z"
              : "M31 139L71 125L110 88H170L222 129L269 140V158H30Z"
        }
        fill={body}
        stroke="#383b40"
        strokeWidth="2"
      />
      {type !== 0 && (
        <path
          d={type === 1 ? "M68 95H199L224 124H60Z" : "M113 96H168L201 124H88Z"}
          fill="#7f9a9f"
        />
      )}
      <path
        d="M99 123V111Q103 98 115 111V124M154 124V111Q159 98 172 112V126"
        fill={["#9b6c4f", "#88817a", "#915e70"][inside ?? 0]}
      />
      <path d="M74 127L69 104" stroke="#495961" strokeWidth="4" />
      <path d="M130 129V155M214 136V152" stroke="#fff" opacity=".25" />
      <path d="M263 139H272V147H259Z" fill="#f8e3a6" />
      <path d="M30 139H38V146H30Z" fill="#b72c31" />
      {[76, 224].map((x) => (
        <g key={x}>
          <circle cx={x} cy="158" r="22" fill="#333238" />
          <circle
            cx={x}
            cy="158"
            r="14"
            fill={wheels === 2 ? "#454650" : "#d2c6b7"}
          />
          {wheels === 0 ? (
            [0, 60, 120].map((a) => (
              <path
                key={a}
                d={"M" + x + " 146V170"}
                stroke="#5c5e65"
                strokeWidth="2"
                transform={"rotate(" + a + " " + x + " 158)"}
              />
            ))
          ) : (
            <circle
              cx={x}
              cy="158"
              r="7"
              fill={wheels === 1 ? "#f0e8d9" : "#303038"}
            />
          )}
        </g>
      ))}
      {extra === 0 && type !== 0 && (
        <path d="M118 90H168" stroke="#cbd7d5" strokeWidth="5" />
      )}
      {extra === 1 && (
        <g fill="#e7c18b">
          <circle cx="144" cy="124" r="5" />
          <circle cx="184" cy="124" r="5" />
        </g>
      )}
      {extra === 2 && (
        <path
          d="M110 95Q115 89 110 83M163 95Q168 89 163 83"
          stroke="#f6cb95"
          fill="none"
          strokeWidth="2"
        />
      )}
    </svg>
  );
}
