(** Request bodies for creating legal persons. A legal person is created with "claims",
    one per fact (identity, residence, tax residency, ...). *)

open! Core

(** An individual with every claim the sandbox "Individual - Account Owners" (Verify)
    workflow requires. Only the name, birth date and email vary; the rest is fixed test
    data (a UK resident employee, GB tax resident, not a US citizen). Sandbox only: the
    sandbox terms allow only test data. *)
val sandbox_individual
  :  display_name:string
  -> given_name:string
  -> surname:string
  -> date_of_birth:Date.t
  -> email:string
  -> Yojson.Safe.t

(** A legal person body from arbitrary claims (each a JSON object with [claim-type]). *)
val legal_person
  :  display_name:string
  -> legal_person_type:[ `Individual | `Corporation ]
  -> claims:Yojson.Safe.t list
  -> Yojson.Safe.t
