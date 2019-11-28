module EAC where
open import Logic
open import Maybe
open import Nat
open import List
open import Equality
open import EquationalReasoning

-- ::::::::::::::
-- :: Language ::
-- ::::::::::::::

-- A λ-calculus term. We're keeping types as simple as possible, so we don't
-- keep a Fin index tracking free vars, nor contexts in any form
data Term : Set where
  var : Nat -> Term
  lam : Term -> Term
  app : Term -> Term -> Term
  box : Term -> Term
  dup : Term -> Term -> Term

infixr 6 _=>_
data Type : Set where
  τ  : Type
  _=>_ : Type -> Type -> Type
  !    : Type -> Type

Context = List Type

-- A proof of x ∈ xs is the index into xs where x is located.
infix 2 _∈_
data _∈_ {A : Set} (x : A) : List A → Set where
  zero : ∀ {xs} → x ∈ x :: xs
  succ : ∀ {y xs} → x ∈ xs → x ∈ y :: xs

rawIndex : ∀ {A} {x : A} {xs} → x ∈ xs → Nat
rawIndex zero    = zero
rawIndex (succ i) = succ (rawIndex i)

data ofType (Γ : Context) : Term → Type → Set where
  var : ∀ {A} (x : A ∈ Γ) → ofType Γ (var (rawIndex x)) A
  app : ∀ {A B fun arg} → ofType Γ fun (A => B) → ofType Γ arg A → ofType Γ (app fun arg) B
  lam : ∀ {A B bod} → ofType (A :: Γ) bod B → ofType Γ (lam bod) (A => B)
  box : ∀ {A bod} → ofType Γ bod A -> ofType Γ (box bod) (! A)
  dup : ∀ {A B arg bod} → ofType Γ arg (! A) -> ofType (A :: (A :: Γ)) bod B -> ofType Γ (dup arg bod) B

WellTyped : Context → Term → Set
WellTyped Γ t = Sum Type (ofType Γ t)

-- Closed terms that are well-typed
WellTyped* : Term → Set
WellTyped* e = WellTyped [] e

-- Adjusts a renaming function
shift-fn : (Nat -> Nat) -> Nat -> Nat
shift-fn fn zero     = zero
shift-fn fn (succ i) = succ (fn i)

shift-fn-many : Nat -> (Nat -> Nat) -> Nat -> Nat
shift-fn-many n fn = pow shift-fn n fn

-- Renames all free variables with a renaming function, `fn`
shift : (Nat -> Nat) -> Term -> Term
shift fn (var i)       = var $ fn i
shift fn (lam bod)     = lam $ shift (shift-fn fn) bod
shift fn (box bod)     = box $ shift fn bod
shift fn (app fun arg) = app (shift fn fun) (shift fn arg)
shift fn (dup arg bod) = dup (shift fn arg) (shift (shift-fn (shift-fn fn)) bod)

-- Adjusts a substitution map
subst-fn : (Nat → Term) → Nat → Term
subst-fn fn zero     = var zero
subst-fn fn (succ i) = shift succ (fn i)

-- Creates a substitution map that replaces only one variable
at : Nat → Term → Nat → Term
at 0        term 0     = term
at 0        term (succ i) = var i
at (succ n) term = subst-fn (at n term)

-- Substitutes all free vars on term with a substitution map, `fn`
subst : (Nat -> Term) -> Term -> Term
subst fn (var i)       = fn i
subst fn (lam bod)     = lam $ subst (subst-fn fn) bod
subst fn (box bod)     = box $ subst fn bod
subst fn (app fun arg) = app (subst fn fun) (subst fn arg)
subst fn (dup arg bod) = dup (subst fn arg) (subst (subst-fn (subst-fn fn)) bod)

shift-type-var : ∀ {A Γ i B} → ofType Γ (var i) B → ofType (A :: Γ) (var (succ i)) B
shift-type-var (var pf) = var (succ pf)

shift-type-lemma-aux : ∀ Δ {A Γ t B} → ofType (Δ ++ Γ) t B → ofType (Δ ++ A :: Γ) (shift (shift-fn-many (length Δ) succ) t) B
shift-type-lemma-aux Δ {A} {Γ} {var _} {B} (var pf)        with Δ
shift-type-lemma-aux Δ {A} {Γ} {var _} {B} (var pf)        | []      = var (succ pf)
shift-type-lemma-aux Δ {A} {Γ} {var _} {B} (var zero)      | C :: Δ' = var zero
shift-type-lemma-aux Δ {A} {Γ} {var _} {B} (var (succ pf)) | C :: Δ' = shift-type-var $ shift-type-lemma-aux Δ' (var pf)
shift-type-lemma-aux Δ {A} {Γ} {lam t} {C => B} (lam pf)             = lam $ shift-type-lemma-aux (C :: Δ) pf
shift-type-lemma-aux Δ {A} {Γ} {box t} { ! B } (box pf)              = box $ shift-type-lemma-aux Δ pf
shift-type-lemma-aux Δ {A} {Γ} {app t s} {B} (app pf_t pf_s)         = app (shift-type-lemma-aux Δ pf_t) (shift-type-lemma-aux Δ pf_s)
shift-type-lemma-aux Δ {A} {Γ} {dup t s} {B} (dup {C} pf_t pf_s)     = dup (shift-type-lemma-aux Δ pf_t) (shift-type-lemma-aux (C :: C :: Δ) pf_s)

shift-type-lemma : ∀ {A Γ t B} → ofType Γ t B → ofType (A :: Γ) (shift succ t) B
shift-type-lemma pf = shift-type-lemma-aux [] pf

-- Cut rule
cut_aux : (Δ Γ : Context) (A B : Type) (bod arg : Term) -> ofType (Δ ++ A :: Γ) bod B -> ofType Γ arg A -> ofType (Δ ++ Γ) (subst (at (length Δ) arg) bod) B
cut_aux Δ Γ A B (var _) arg (var pf1) pf2                with rawIndex pf1 | inspect rawIndex pf1
cut_aux [] Γ A A (var _) arg (var zero) pf2              | 0               | its _ = pf2
cut_aux (B :: Δ) Γ A B (var _) arg (var zero) pf2        | 0               | its _ = var zero
cut_aux [] (C :: Γ) A B (var _) arg (var (succ pf1)) pf2 | succ n          | its eq = rwt (λ x → ofType (C :: Γ) (var x) B) (succ-inj eq) (var pf1)
cut_aux (C :: Δ) Γ  A B (var _) arg (var (succ pf1)) pf2 | succ n          | its eq =
  let oftype = rwt (λ x → ofType (Δ ++ Γ) (at (length Δ) arg x) B) (succ-inj eq) $ cut_aux Δ Γ A B (var _)  arg (var pf1) pf2
  in shift-type-lemma oftype
cut_aux Δ Γ A (C => B) (lam t) arg (lam pf1) pf2      = lam $ cut_aux (C :: Δ) Γ A B t arg pf1 pf2
cut_aux Δ Γ A (! B) (box t) arg (box pf1) pf2         = box $ cut_aux Δ Γ A B t arg pf1 pf2
cut_aux Δ Γ A B (app t s) arg (app {C} pf_t pf_s) pf2 = app (cut_aux Δ Γ A (C => B) t arg pf_t pf2) (cut_aux Δ Γ A C s arg pf_s pf2)
cut_aux Δ Γ A B (dup t s) arg (dup {C} pf_t pf_s) pf2 = dup (cut_aux Δ Γ A (! C) t arg pf_t pf2) (cut_aux (C :: C :: Δ) Γ A B s arg pf_s pf2)

cut : (Γ : Context) (A B : Type) (bod arg : Term) -> ofType (A :: Γ) bod B -> ofType Γ arg A -> ofType Γ (subst (at 0 arg) bod) B
cut = cut_aux []

-- Computes how many times a free variable is used
uses : Term -> Nat -> Nat
uses (var idx')    idx with same idx' idx
uses (var idx')    idx | true  = 1
uses (var idx')    idx | false = 0
uses (lam bod)     idx = uses bod (1 + idx)
uses (app fun arg) idx = uses fun idx + uses arg idx
uses (box bod)     idx = uses bod idx
uses (dup arg bod) idx = uses arg idx + uses bod (2 + idx)

-- Checks whether all occurences of a free variable are in a specific level
at-level-aux : Nat -> Term -> Nat -> Nat -> Bool
at-level-aux current-lvl (var idx')    idx lvl with same idx' idx
at-level-aux current-lvl (var idx')    idx lvl | true  = same current-lvl lvl
at-level-aux current-lvl (var idx')    idx lvl | false = true
at-level-aux current-lvl (lam bod)     idx lvl = at-level-aux current-lvl bod (1 + idx) lvl
at-level-aux current-lvl (app fun arg) idx lvl = at-level-aux current-lvl fun idx lvl && at-level-aux current-lvl arg idx lvl
at-level-aux current-lvl (box bod)     idx lvl = at-level-aux (succ current-lvl) bod idx lvl
at-level-aux current-lvl (dup bod arg) idx lvl = at-level-aux current-lvl bod idx lvl && at-level-aux current-lvl bod (2 + idx) lvl

at-level : Term -> Nat -> Nat -> Bool
at-level term idx lvl = at-level-aux 0 term idx lvl

at-level-affine : Term -> Nat -> Nat -> Bool
at-level-affine term idx lvl with uses term idx
at-level-affine term idx lvl | 0 = true
at-level-affine term idx lvl | 1 = at-level term idx lvl
at-level-affine term idx lvl | succ (succ _) = false

-- Performs a global reduction of all current redexes
reduce : (Γ : Context) (t : Term) (A : Type) -> ofType Γ t A -> Sum Term (λ t → ofType Γ t A)
-- traverses
reduce Γ (var i) A (var pf) = sigma (var i) (var pf)
reduce Γ (lam t) (A => B) (lam pf) =
  let sigma t' pf' = reduce (A :: Γ) t B pf
  in sigma (lam t') (lam pf')
reduce Γ (box t) (! A) (box pf) =
  let sigma t' pf' = reduce Γ t A pf
  in sigma (box t') (box pf') 
reduce Γ (app (var i) t) A (app {C} pf1 pf2) = 
  let sigma x pf1' = reduce Γ (var i) (C => A) pf1
      sigma t' pf2' = reduce Γ t C pf2
  in sigma (app x t') (app pf1' pf2')
reduce Γ (app (app t s) r) A (app {C} pf1 pf2) =
  let sigma x pf1' = reduce Γ (app t s) (C => A) pf1
      sigma r' pf2' = reduce Γ r C pf2
  in sigma (app x r') (app pf1' pf2')
reduce Γ (dup (var i) t) A (dup {C} pf1 pf2) =
  let sigma x pf1' = reduce Γ (var i) (! C) pf1
      sigma t' pf2' = reduce (C :: C :: Γ) t A pf2
  in sigma (dup x t') (dup pf1' pf2')
reduce Γ (dup (app t s) r) A (dup {C} pf1 pf2) =
  let sigma x pf1' = reduce Γ (app t s) (! C) pf1
      sigma r' pf2' = reduce (C :: C :: Γ) r A pf2
  in sigma (dup x r') (dup pf1' pf2')
-- swaps
reduce Γ (app (dup t s) r) A (app {C} (dup {D} pf1 pf2) pf3) =
  let term = dup t (app s (shift succ (shift succ r)))
      type = dup pf1 (app pf2 (shift-type-lemma (shift-type-lemma pf3)))
  in sigma term type
reduce Γ (dup (dup t s) r) A (dup {C} (dup {D} pf1 pf2) pf3) =
  let term =  dup t (dup s (shift (shift-fn-many 2 succ) (shift (shift-fn-many 2 succ) r)))
      type = dup pf1 (dup pf2 (shift-type-lemma-aux (C :: C :: []) {D} (shift-type-lemma-aux (C :: C :: []) {D} pf3)))
  in sigma term type
-- redexes
reduce Γ (app (lam t) s) B (app {A} (lam pf1) pf2) =
  let term = subst (at zero s) t
      type = cut Γ A B t s pf1 pf2
  in sigma term type
reduce Γ (dup (box t) s) B (dup {A} (box pf1) pf2) =
  let term = subst (at zero t) (subst (at zero (shift succ t)) s)
      type' = cut (A :: Γ) A B s (shift succ t) pf2 (shift-type-lemma pf1)
      type = cut Γ A B (subst (at 0 (shift succ t)) s) t type' pf1
  in sigma term type

-- Elementary affine term
data EAC : (t : Term) → Set where
  var-eac : ∀ {a} → EAC (var a)
  lam-eac : ∀ {bod} → at-level-affine bod 0 0 == true → EAC bod -> EAC (lam bod)
  app-eac : ∀ {fun arg} → EAC fun → EAC arg -> EAC (app fun arg)
  box-eac : ∀ {bod} → EAC bod → EAC (box bod)
  dup-eac : ∀ {arg bod} → at-level-affine bod 0 1 == true → at-level-affine bod 1 1 == true → EAC arg → EAC bod → EAC (dup arg bod)

-- This term is on normal form
data IsNormal : (t : Term) → Set where
  var-normal : ∀ {a} → IsNormal (var a)
  lam-normal : ∀ {bod} → IsNormal bod -> IsNormal (lam bod)
  box-normal : ∀ {bod} → IsNormal bod -> IsNormal (box bod)
  app-var-normal : ∀ {fidx arg} → IsNormal arg -> IsNormal (app (var fidx) arg)
  app-app-normal : ∀ {ffun farg arg} → IsNormal (app ffun farg) → IsNormal arg -> IsNormal (app (app ffun farg) arg)
  dup-var-normal : ∀ {fidx arg} → IsNormal arg -> IsNormal (dup (var fidx) arg)
  dup-app-normal : ∀ {ffun farg arg} → IsNormal (app ffun farg) → IsNormal arg -> IsNormal (dup (app ffun farg) arg)

-- This term has redexes
data HasRedex : (t : Term) → Set where
  lam-redex : ∀ {bod} → HasRedex bod -> HasRedex (lam bod)
  box-redex : ∀ {bod} → HasRedex bod -> HasRedex (box bod)
  app-redex : ∀ {fun arg} → Or (HasRedex fun) (HasRedex arg) -> HasRedex (app fun arg)
  dup-redex : ∀ {arg bod} → Or (HasRedex arg) (HasRedex bod) -> HasRedex (dup arg bod)
  found-app-redex : ∀ {bod arg} → HasRedex (app (lam bod) arg)
  found-dup-redex : ∀ {bod arg} → HasRedex (dup (box bod) arg)
  found-app-swap : ∀ {bod arg arg'} → HasRedex (app (dup arg arg') bod)
  found-dup-swap : ∀ {bod arg arg'} → HasRedex (dup (dup arg arg') bod)

-- Directed one step reduction relation, `a ~> b` means term `a` reduces to `b` in one step
data _~>_ : Term → Term → Set where
  ~beta : ∀ {t u} → app (lam t) u ~> subst (at 0 u) t
  ~app0 : ∀ {a f0 f1} → f0 ~> f1 → app f0 a ~> app f1 a
  ~app1 : ∀ {f a0 a1} → a0 ~> a1 → app f a0 ~> app f a1
  ~lam0 : ∀ {b0 b1} → b0 ~> b1 → lam b0 ~> lam b1

-- Directed arbitraty step reduction relation, `a ~>> b` means term `a` reduces to `b` in zero or more steps
data _~>>_ : Term → Term → Set where
  ~>>refl  : ∀ {t t'} → t == t' → t ~>> t'
  ~>>trans : ∀ {t t' t''} → t ~>> t'' → t'' ~>> t' → t ~>> t'
  ~>>step  : ∀ {t t'} → t ~> t' → t ~>> t'

data Normalizable : (t : Term) → Set where
  normal-is-normalizable : ∀ {t} → IsNormal t → Normalizable t
  onestep-normalizable : ∀ {t t'} → t ~> t' → Normalizable t' → Normalizable t

-- A normal term has no redexes
normal-has-noredex : (t : Term) → IsNormal t → Not (HasRedex t)
normal-has-noredex (lam bod) (lam-normal x) (lam-redex y)                             = normal-has-noredex bod x y
normal-has-noredex (box bod) (box-normal x) (box-redex y)                             = normal-has-noredex bod x y
normal-has-noredex (app (var idx) arg) (app-var-normal x) (app-redex (or1 y))         = normal-has-noredex arg x y
normal-has-noredex (app (app ffun farg) arg) (app-app-normal x _) (app-redex (or0 y)) = normal-has-noredex (app ffun farg) x y
normal-has-noredex (app (app ffun farg) arg) (app-app-normal _ x) (app-redex (or1 y)) = normal-has-noredex arg x y
normal-has-noredex (dup (var idx) bod) (dup-var-normal x) (dup-redex (or1 y))         = normal-has-noredex bod x y
normal-has-noredex (dup (app ffun farg) bod) (dup-app-normal x _) (dup-redex (or0 y)) = normal-has-noredex (app ffun farg) x y
normal-has-noredex (dup (app ffun farg) bod) (dup-app-normal _ x) (dup-redex (or1 y)) = normal-has-noredex bod x y
