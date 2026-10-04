import { RoomForm } from "@/components/room-form";
export default async function Page({
  searchParams,
}: {
  searchParams: Promise<{ code?: string }>;
}) {
  const { code } = await searchParams;
  return <RoomForm mode="join" initialCode={code?.slice(0, 8)} />;
}
