import { Lobby } from "@/components/lobby";
import { notFound } from "next/navigation";
export default async function Page({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  if (!/^[a-f0-9-]{36}$/i.test(id)) notFound();
  return <Lobby id={id} />;
}
