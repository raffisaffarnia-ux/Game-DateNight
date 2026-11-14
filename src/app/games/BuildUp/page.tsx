import BuildUp from "@/games/buildup/game";
import "@/games/buildup/buildup.css";
export const metadata = {
  title: "BuildUp · DateNight.io",
  robots: { index: false, follow: false },
};
export default async function Page({
  searchParams,
}: {
  searchParams: Promise<{ room?: string; code?: string }>;
}) {
  const { room, code } = await searchParams;
  return <BuildUp roomId={room} invite={code} />;
}
