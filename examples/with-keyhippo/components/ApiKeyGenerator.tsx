"use client";
import { useState, useEffect, useRef } from "react";
import { createClient } from "@/utils/supabase/client";
import { KeyHippo } from "keyhippo";
import Code from "./tutorial/Code";

export default function ApiKeyGenerator() {
  const [apiKey, setApiKey] = useState<string | null>(null);
  const effectRan = useRef(false);

  useEffect(() => {
    if (effectRan.current) return;

    const generateApiKey = async () => {
      const supabase = createClient();
      const { data: { user } } = await supabase.auth.getUser();
      const keyhippo = new KeyHippo(supabase);
      const newKey = await keyhippo.createApiKey(user!.id, "example");
      setApiKey(newKey.apiKey);
    };

    generateApiKey();

    return () => {
      effectRan.current = true;
    };
  }, []);

  return (
    <div className="flex flex-col items-center mt-8">
      <h3 className="font-bold text-2xl mb-2 text-center">Your API Key:</h3>
      {apiKey ? (
        <div className=" p-4 rounded text-center max-w-lg">
          <Code code={apiKey}/>
          <p className="mt-2 text-red-500 font-bold">
            Make sure to copy your key now, it can't be seen again!
          </p>
        </div>
      ) : (
        <p className="text-lg">Generating API key...</p>
      )}
    </div>
  );
}
