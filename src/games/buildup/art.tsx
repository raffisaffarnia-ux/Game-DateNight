import { RoomScene, PizzaScene, CarScene } from "./scenes";
import { Photo } from "./photo";
import type { Topic } from "./topics";
const jacket = ["#272936", "#283f62", "#813957", "#efe2cf"];
const shirt = ["#f8f5ec", "#34313c", "#b2d0e6", "#edb5c5"];
const ties = ["#27283b", "#98334d", "#304565"];
const pants = ["#292932", "#344660", "#d7c5a8", "#585962"];
const shoes = ["#25252b", "#865c43", "#343036", "#faf5ea"];
export function Outfit({ picks }: { picks: number[] }) {
  const [j, h, t, p, s] = picks;
  return (
    <svg
      viewBox="0 0 180 210"
      role="img"
      aria-label="Dein zusammengestelltes Ball-Outfit"
    >
      <ellipse cx="90" cy="200" rx="49" ry="5" fill="#32253a" opacity=".25" />
      <path
        d="M66 105H114L112 181H94L90 134L85 181H66Z"
        fill={pants[p] ?? "#88808a"}
      />
      <path
        d="M84 17Q89 23 96 17V30L110 36L90 56L72 36L84 30Z"
        fill="#bd977d"
      />
      <path
        d="M74 32L85 28L90 34L96 28L109 32L104 105H74Z"
        fill={shirt[h] ?? "#d2c6b9"}
      />
      {t !== undefined && t < 3 && (
        <path d="M86 35H94L92 41L95 68L90 74L85 68L88 41Z" fill={ties[t]} />
      )}
      <path
        d="M74 30L81 28L90 76L89 111L62 109L64 58L55 92L43 89L53 45Q56 35 74 30ZM106 30L99 28L90 76L91 111L118 109L116 58L125 92L137 89L127 45Q124 35 106 30Z"
        fill={jacket[j] ?? "#655b6a"}
      />
      <path
        d="M76 31L69 46L77 48L73 54L89 75M104 31L111 46L103 48L107 54L91 75"
        fill="none"
        stroke="#fff"
        opacity=".36"
        strokeWidth="2"
      />
      <path
        d="M99 61H110M72 91H81M100 91H109"
        stroke="#e4c69b"
        strokeWidth="2"
      />
      <circle cx="92" cy="82" r="1.8" fill="#e4c69b" />
      <path
        d={
          s === 2
            ? "M65 182H84V190H56Q54 185 65 182ZM95 182H112L124 188V190H95Z"
            : "M65 181H85V194H53Q50 187 65 181ZM94 181H113Q126 185 126 194H94Z"
        }
        fill={shoes[s] ?? "#777179"}
      />
    </svg>
  );
}
export function Artwork({ topic, picks }: { topic: Topic; picks: number[] }) {
  if (topic.id === "ball") return <Outfit picks={picks} />;
  if (topic.id === "room") return <RoomScene picks={picks} />;
  if (topic.id === "pizza") return <PizzaScene picks={picks} />;
  if (topic.id === "car") return <CarScene picks={picks} />;
  return (
    <div className="bu-mosaic" aria-label="Deine Kreation">
      {topic.steps.map((step, i) => (
        <div key={step.label} data-filled={picks[i] !== undefined}>
          <span className="bu-mosaic-image">
            {picks[i] === undefined ? (
              <span className="bu-empty-part">+</span>
            ) : (
              <Photo
                key={i + "-" + picks[i]}
                topic={topic}
                step={i}
                option={picks[i]}
              />
            )}
          </span>
          <small>{step.options[picks[i]] ?? step.label}</small>
        </div>
      ))}
    </div>
  );
}
