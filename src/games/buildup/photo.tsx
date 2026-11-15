import { createContext, useContext, useState } from "react";
import type { Topic } from "./topics";
import { localPhoto, breakfast } from "./assets";
import { Illustration } from "./illustrations";
export type PhotoAsset = { src: string; author: string; link: string };
export const PhotoContext = createContext<Record<string, PhotoAsset>>({});

export function Photo({
  topic,
  step,
  option,
}: {
  topic: Topic;
  step: number;
  option: number;
}) {
  const [failed, setFailed] = useState(false);
  const manifest = useContext(PhotoContext);
  const external = manifest[topic.id + ":" + step + ":" + option];
  const local = localPhoto(topic.id, step, option);
  const photo = external ?? local;
  if (photo && !failed) {
    return (
      <img
        src={photo.src}
        loading="lazy"
        alt={topic.steps[step].options[option]}
        onError={() => setFailed(true)}
      />
    );
  }
  return <Illustration topic={topic.id} step={step} option={option} />;
}
export function PhotoCredits() {
  const manifest = useContext(PhotoContext);
  const unique = [
    ...new Map(Object.values(manifest).map((p) => [p.link, p])).values(),
  ];

  return (
    <details className="bu-credits">
      <summary>Bildnachweise</summary>
      {breakfast.map((photo) => (
        <a key={photo.link} href={photo.link} target="_blank" rel="noreferrer">
          {photo.author} auf Unsplash
        </a>
      ))}
      {unique.map((photo) => (
        <a key={photo.link} href={photo.link} target="_blank" rel="noreferrer">
          {photo.author} auf Pexels
        </a>
      ))}
    </details>
  );
}
