import { Navbar } from "@/components/navbar"
import { CreateWizard } from "@/components/create_wpg"


export default function Page() {
  return (
    <main className="min-h-screen">
      <Navbar />
      <div className="container mx-auto px-4 pt-6">
        <CreateWizard />
      </div>
    </main>
  )
}
