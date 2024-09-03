import Link from "next/link";
import { createClient } from "@/utils/supabase/server";
import { redirect } from "next/navigation";

export default async function Login({
  searchParams,
}: {
  searchParams: { message: string };
}) {
  const signInAnonymously = async () => {
    'use server';
    const supabase = createClient();
    const { data, error } = await supabase.auth.signInAnonymously();

    if (error) {
      console.error("Authentication error:", error);
      return redirect("/login?message=Could not authenticate user");
    }

    if (data?.session) {
      return redirect("/protected");
    } else {
      console.error("No session data returned");
      return redirect("/login?message=Authentication failed");
    }
  };

  return (
    <div className="flex-1 flex flex-col w-full px-8 sm:max-w-md justify-center gap-2">
      <Link
        href="/"
        className="absolute left-8 top-8 py-2 px-4 rounded-md no-underline text-foreground bg-btn-background hover:bg-btn-background-hover flex items-center group text-sm"
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="24"
          height="24"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
          className="mr-2 h-4 w-4 transition-transform group-hover:-translate-x-1"
        >
          <polyline points="15 18 9 12 15 6" />
        </svg>{" "}
        Back
      </Link>
      <div className="flex-1 flex flex-col w-full justify-center gap-2 text-foreground">
        <form action={signInAnonymously}>
          <button
            className="bg-green-700 rounded-md px-4 py-2 text-foreground mb-2 w-full"
            type="submit"
          >
            Continue Anonymously
          </button>
        </form>
        {searchParams?.message && (
          <p className="mt-4 p-4 bg-foreground/10 text-foreground text-center">
            {searchParams.message}
          </p>
        )}
      </div>
    </div>
  );
}
