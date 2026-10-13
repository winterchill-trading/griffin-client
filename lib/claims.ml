open! Core

let legal_person ~display_name ~legal_person_type ~claims =
  `Assoc
    [ "display-name", `String display_name
    ; ( "legal-person-type"
      , `String
          (match legal_person_type with
           | `Individual -> "individual"
           | `Corporation -> "corporation") )
    ; "claims", `List claims
    ]
;;

let claim ty fields = `Assoc (("claim-type", `String ty) :: fields)
let gbp v = `Assoc [ "currency", `String "GBP"; "value", `String v ]
let strings l = `List (List.map l ~f:(fun s -> `String s))

let sandbox_individual ~display_name ~given_name ~surname ~date_of_birth ~email =
  legal_person
    ~display_name
    ~legal_person_type:`Individual
    ~claims:
      [ claim
          "individual-identity"
          [ "given-name", `String given_name
          ; "surname", `String surname
          ; "date-of-birth", `String (Date.to_string date_of_birth)
          ]
      ; claim "contact-details" [ "email-address", `String email ]
      ; claim
          "individual-residence"
          [ "building-number", `String "1"
          ; "street-name", `String "Example Street"
          ; "city", `String "Test Town"
          ; "postal-code", `String "TE1 2ST"
          ; "country-code", `String "GB"
          ]
      ; claim "mobile-number" [ "mobile-number", `String "+442012345678" ]
      ; claim
          "employment"
          [ "employment-status", `String "employed"
          ; "occupation", `String "construction-worker"
          ; "industry-of-occupation", `String "property-and-construction"
          ]
      ; claim "individual-income" [ "income", gbp "50000.00" ]
      ; claim "nationality" [ "nationality", `String "GB" ]
      ; claim "tax-residencies" [ "tax-residencies", strings [ "GB" ] ]
      ; claim "us-citizen" [ "us-citizen?", `Bool false ]
      ; claim
          "individual-purposes-of-account"
          [ "individual-purposes-of-account", strings [ "everyday-spending" ] ]
      ; claim
          "individual-sources-of-funds"
          [ "individual-sources-of-funds", strings [ "savings" ] ]
      ; claim "cash-payments" [ "cash-payments?", `Bool false ]
      ; claim "initial-deposit" [ "initial-deposit", gbp "100.00" ]
      ; claim
          "international-payments-countries"
          [ "international-payments-countries", strings [ "FR" ] ]
      ]
;;
