Require Import mailbox.verif_atomics.
Require Import progs.conclib.
Require Import progs.ghost.
Require Import floyd.library.
Require Import floyd.sublist.
Require Import mailbox.hashtable1.

Set Bullet Behavior "Strict Subproofs".

Instance CompSpecs : compspecs. make_compspecs prog. Defined.
Definition Vprog : varspecs. mk_varspecs prog. Defined.

Definition surely_malloc_spec :=
 DECLARE _surely_malloc
   WITH n:Z
   PRE [ _n OF tuint ]
       PROP (0 <= n <= Int.max_unsigned)
       LOCAL (temp _n (Vint (Int.repr n)))
       SEP ()
    POST [ tptr tvoid ] EX p:_,
       PROP ()
       LOCAL (temp ret_temp p)
       SEP (malloc_token Tsh n p * memory_block Tsh n p).

Definition integer_hash_spec :=
 DECLARE _integer_hash
  WITH i : Z
  PRE [ _i OF tint ]
   PROP () LOCAL (temp _i (vint i)) SEP ()
  POST [ tint ]
   PROP () LOCAL (temp ret_temp (vint (i * 654435761))) SEP ().
(* One might think it should just return an unknown number, but in fact it needs to follow a known hash
   function at the logic level to be useful. *)

Definition tentry := Tstruct _entry noattr.

Definition entry_hists entries hists := fold_right sepcon emp (map (fun i =>
  let '(hp, e) := (Znth i hists ([], []), Znth i entries Vundef) in
    ghost_hist (fst hp) (field_address tentry [StructField _key] e) *
    ghost_hist (snd hp) (field_address tentry [StructField _value] e)) (upto 32)).

(* up *)
Lemma Znth_cons : forall {A} (d : A) i x l, Znth i (x :: l) d = if eq_dec i 0 then x else Znth (i - 1) l d.
Proof.
  intros.
  destruct (eq_dec i 0); [subst; apply Znth_0_cons|].
  destruct (zlt i 0); [rewrite !Znth_underflow; auto; omega|].
  apply Znth_pos_cons; omega.
Qed.

(* Maps are represented as partial association lists, with entries with key 0 considered to be empty. *)
Fixpoint index_of (m : list (Z * Z)) (k : Z) :=
  match m with
  | [] => None
  | (k1, v1) :: rest => if eq_dec k1 k then Some 0
                        else option_map Z.succ (index_of rest k)
  end.

Lemma index_of_spec : forall k m, match index_of m k with
  | Some i => 0 <= i < Zlength m /\ fst (Znth i m (0, 0)) = k /\ Forall (fun x => fst x <> k) (sublist 0 i m)
  | None => ~In k (map fst m) end.
Proof.
  induction m; simpl; auto; intros.
  destruct a.
  rewrite Zlength_cons.
  pose proof (Zlength_nonneg m).
  destruct (eq_dec z k).
  { split; [omega|].
    rewrite sublist_nil; auto. }
  destruct (index_of m k); simpl.
  - destruct IHm as (? & ? & ?); unfold Z.succ.
    rewrite Znth_cons, Z.add_simpl_r.
    if_tac; [omega|].
    split; [omega|].
    split; auto.
    rewrite sublist_0_cons, Z.add_simpl_r by omega; constructor; auto.
  - tauto.
Qed.

(* Abstract properties of hashtables (of length 32) *)
Definition hash i := (i * 654435761) mod 32.

Definition well_chained (m : list (Z * Z)) := forall k i, index_of (rotate m (hash k) (Zlength m)) k = Some i ->
  Forall (fun x => fst x <> 0) (sublist 0 i (rotate m (hash k) (Zlength m))).

Definition wf_map (m : list (Z * Z)) := NoDup (map fst m).

Definition indices i j := (map (fun x => (i + x) mod 32) (upto (Z.to_nat ((j - i) mod 32)))).

Fixpoint index_of' (m : list (Z * Z)) k :=
  match m with
  | [] => None
  | (k1, v1) :: rest => if eq_dec k1 0 then None else
                        if eq_dec k1 k then Some 0
                        else option_map Z.succ (index_of' rest k)
  end.

Lemma index_of'_spec : forall k m, match index_of' m k with
  | Some i => k <> 0 /\ 0 <= i < Zlength m /\ fst (Znth i m (0, 0)) = k /\
              Forall (fun x => fst x <> 0 /\ fst x <> k) (sublist 0 i m)
  | None => ~In k (map fst m) \/ exists i, 0 <= i < Zlength m /\ fst (Znth i m (0, 0)) = 0 /\
            Forall (fun x => fst x <> 0 /\ fst x <> k) (sublist 0 i m) end.
Proof.
  induction m; simpl; auto; intros.
  destruct a.
  rewrite Zlength_cons.
  pose proof (Zlength_nonneg m).
  destruct (eq_dec z 0).
  { subst; right.
    exists 0; split; [omega|].
    rewrite sublist_nil, Znth_cons; split; auto. }
  destruct (eq_dec z k).
  { subst; split; auto.
    split; [omega|].
    rewrite sublist_nil, Znth_cons; split; auto. }
  destruct (index_of' m k); simpl.
  - destruct IHm as (? & ? & ? & ?); unfold Z.succ; rewrite Znth_cons, Z.add_simpl_r.
    split; auto.
    if_tac; [omega|].
    split; [omega|].
    split; auto.
    rewrite sublist_0_cons, Z.add_simpl_r by omega; constructor; auto.
  - destruct IHm as [? | (i & ? & ? & ?)]; [tauto|].
    right; exists (i + 1).
    split; [omega|].
    rewrite Znth_cons, sublist_0_cons, !Z.add_simpl_r by omega; if_tac; auto; omega.
Qed.

Definition lookup (m : list (Z * Z)) (k : Z) :=
  option_map (fun i => (i - hash k) mod 32) (index_of' (rotate m (hash k) 32) k).

(* up *)
Lemma NoDup_Znth_inj : forall {A} (d : A) l i j (HNoDup : NoDup l)
  (Hi : 0 <= i < Zlength l) (Hj : 0 <= j < Zlength l) (Heq : Znth i l d = Znth j l d),
  i = j.
Proof.
  induction l; intros.
  { rewrite Zlength_nil in *; omega. }
  inv HNoDup.
  rewrite Zlength_cons in *.
  rewrite !Znth_cons in Heq.
  destruct (eq_dec i 0), (eq_dec j 0); subst; auto.
  - contradiction H1; apply Znth_In; omega.
  - contradiction H1; apply Znth_In; omega.
  - exploit (IHl (i - 1) (j - 1)); auto; omega.
Qed.

(* up *)
Lemma Znth_rotate : forall {A} (d : A) i l n, 0 <= n <= Zlength l -> 0 <= i < Zlength l ->
  Znth i (rotate l n (Zlength l)) d = Znth ((i - n) mod Zlength l) l d.
Proof.
  intros; unfold rotate.
  destruct (zlt i n).
  - rewrite app_Znth1 by (rewrite Zlength_sublist; omega).
    rewrite Znth_sublist by omega.
    rewrite <- Z_mod_plus with (b := 1), Zmod_small by omega.
    f_equal; omega.
  - rewrite app_Znth2; (rewrite Zlength_sublist; try omega).
    rewrite Znth_sublist by omega.
    rewrite Zmod_small by omega.
    f_equal; omega.
Qed.

Lemma hash_range : forall i, 0 <= hash i < 32.
Proof.
  intro; apply Z_mod_lt; computable.
Qed.

Lemma rotate_In : forall {A} (x : A) n m l, 0 <= m - n <= Zlength l -> In x (rotate l n m) <-> In x l.
Proof.
  unfold rotate; intros.
  replace l with (sublist 0 (m - n) l ++ sublist (m - n) (Zlength l) l) at 4
    by (rewrite sublist_rejoin, sublist_same; auto; omega).
  rewrite !in_app; tauto.
Qed.

Lemma index_of_app : forall k m1 m2, index_of (m1 ++ m2) k =
  match index_of m1 k with Some i => Some i | None => option_map (Z.add (Zlength m1)) (index_of m2 k) end.
Proof.
  induction m1; simpl; intros.
  - destruct (index_of m2 k); auto.
  - destruct a.
    destruct (eq_dec z k); auto.
    rewrite IHm1; destruct (index_of m1 k); auto; simpl.
    destruct (index_of m2 k); auto; simpl.
    rewrite Zlength_cons; f_equal; omega.
Qed.

Lemma index_of_out : forall k m, Forall (fun x => fst x <> k) m -> index_of m k = None.
Proof.
  intros.
  pose proof (index_of_spec k m) as Hk.
  destruct (index_of m k); auto.
  destruct Hk; eapply Forall_Znth in H; eauto.
  subst; contradiction H; eauto.
Qed.

Lemma index_of_sublist : forall m a b i k (HNoDup : NoDup (map fst m))
  (Hi : index_of (sublist a b m) k = Some i) (Ha : 0 <= a) (Hb : b <= Zlength m),
  index_of m k = Some (i + a).
Proof.
  intros.
  destruct (Z_le_dec b a); [rewrite sublist_nil_gen in Hi by auto; discriminate|].
  assert (m = sublist 0 a m ++ sublist a b m ++ sublist b (Zlength m) m) as Hm.
  { rewrite !sublist_rejoin, sublist_same; auto; omega. }
  rewrite Hm, index_of_app, index_of_out, index_of_app, Hi; simpl.
  rewrite Zlength_sublist by omega.
  f_equal; omega.
  { rewrite Hm, !map_app in HNoDup; apply NoDup_app in HNoDup.
    destruct HNoDup as (_ & _ & HNoDup).
    rewrite Forall_forall; intros ???.
    exploit (HNoDup k); try contradiction.
    * rewrite in_map_iff; eauto.
    * rewrite in_app; left.
      pose proof (index_of_spec k (sublist a b m)) as Hspec; rewrite Hi in Hspec.
      destruct Hspec as (? & ? & ?).
      rewrite in_map_iff; do 2 eexists; eauto.
      apply Znth_In; auto. }
Qed.

Lemma index_of_rotate : forall m n k, 0 <= n <= Zlength m -> NoDup (map fst m) ->
  index_of (rotate m n (Zlength m)) k = option_map (fun i => (i + n) mod Zlength m) (index_of m k).
Proof.
  intros.
  destruct (eq_dec (Zlength m) 0).
  { apply Zlength_nil_inv in e; subst.
    unfold rotate; rewrite !sublist_of_nil; auto. }
  unfold rotate; rewrite !index_of_app.
  destruct (index_of (sublist (Zlength m - n) (Zlength m) m) k) eqn: Hk2.
  - pose proof (index_of_spec k (sublist (Zlength m - n) (Zlength m) m)) as Hspec.
    rewrite Hk2 in Hspec; destruct Hspec as (Hrange & ?).
    apply index_of_sublist in Hk2; auto; try omega.
    rewrite Hk2; simpl.
    rewrite Zlength_sublist in Hrange by omega.
    replace (z + _ + _) with (z + Zlength m) by omega.
    rewrite Z.add_mod, Z_mod_same_full, Z.add_0_r, Zmod_mod by auto.
    rewrite Zmod_small; auto; omega.
  - replace (index_of m k) with
      (index_of (sublist 0 (Zlength m - n) m ++ sublist (Zlength m - n) (Zlength m) m) k)
      by (rewrite sublist_rejoin, sublist_same; auto; omega).
    rewrite index_of_app, Hk2.
    pose proof (index_of_spec k (sublist 0 (Zlength m - n) m)) as Hspec.
    destruct (index_of (sublist 0 (Zlength m - n) m) k); auto; simpl.
    rewrite Zlength_sublist in Hspec by omega.
    rewrite Zlength_sublist, Zmod_small by omega.
    f_equal; omega.
Qed.

Lemma Forall_sublist_first : forall {A} (P : A -> Prop) i j l d
  (Hrangei : 0 <= i <= Zlength l) (Hi : Forall P (sublist 0 i l)) (Hi' : ~P (Znth i l d))
  (Hrangej : 0 <= j <= Zlength l) (Hj : Forall P (sublist 0 j l)) (Hj' : ~P (Znth j l d)),
  i = j.
Proof.
  intros.
  destruct (zlt i j); [|destruct (zlt j i); [|omega]].
  - eapply Forall_Znth with (i0 := i) in Hj; [|rewrite Zlength_sublist; omega].
    rewrite Znth_sublist, Z.add_0_r in Hj by omega.
    contradiction Hi'; eauto.
  - eapply Forall_Znth with (i0 := j) in Hi; [|rewrite Zlength_sublist; omega].
    rewrite Znth_sublist, Z.add_0_r in Hi by omega.
    contradiction Hj'; eauto.
Qed.

Lemma index_of'_succeeds : forall k m i (Hi : 0 <= i < Zlength m)
  (Hnz : Forall (fun x => fst x <> 0 /\ fst x <> k) (sublist 0 i m))
  (Hk : fst (Znth i m (0, 0)) = k) (Hk' : k <> 0), index_of' m k = Some i.
Proof.
  intros.
  pose proof (index_of'_spec k m).
  destruct (index_of' m k).
  - destruct H as (? & ? & Hz & Hnz').
    f_equal; eapply Forall_sublist_first; eauto; simpl; try omega.
    + rewrite Hz; tauto.
    + rewrite Hk; tauto.
  - destruct H as [? | (z & ? & Hz & ?)].
    + contradiction H.
      rewrite in_map_iff; do 2 eexists; eauto.
      apply Znth_In; omega.
    + assert (z = i); [|subst; contradiction Hk'].
      eapply Forall_sublist_first; eauto; simpl; try omega.
      * rewrite Hz; tauto.
      * rewrite Hk; tauto.
Qed.

Lemma lookup_spec : forall m k (Hwf : wf_map m) (Hchain : well_chained m) (Hlen : Zlength m = 32)
  (Hnz : k <> 0), lookup m k = index_of m k.
Proof.
  intros.
  destruct (eq_dec (Zlength m) 0).
  { apply Zlength_nil_inv in e; subst.
    unfold lookup, rotate; rewrite !sublist_of_nil; auto. }
  specialize (Hchain k).
  pose proof (hash_range k).
  assert (0 <= hash k <= Zlength m) by omega.
  rewrite index_of_rotate in Hchain by auto.
  unfold lookup.
  pose proof (index_of_spec k m) as Hspec; destruct (index_of m k) eqn: Hk.
  - specialize (Hchain _ eq_refl).
    destruct Hspec as (? & Hz & ?).
    assert (0 <= (z + hash k) mod Zlength m < Zlength m) by (apply Z_mod_lt; omega).
    assert (((z + hash k) mod Zlength m - hash k) mod Zlength m = z) as Hmod.
    { rewrite Zminus_mod_idemp_l, Z.add_simpl_r, Zmod_small; auto. }
    assert (fst (Znth ((z + hash k) mod Zlength m) (rotate m (hash k) 32) (0, 0)) = k).
    { rewrite <- Hlen, Znth_rotate, Hmod; auto. }
    erewrite index_of'_succeeds; eauto; simpl.
    rewrite <- Hlen, Hmod; auto.
    + rewrite Zlength_rotate; auto; omega.
    + rewrite Forall_forall; intros ? Hin.
      split; [rewrite Forall_forall in Hchain; apply Hchain; rewrite !Hlen in *; auto|].
      intro Heq; apply In_Znth with (d := (0, 0)) in Hin.
      destruct Hin as (i & Hi & ?); subst x.
      rewrite Zlength_sublist in Hi; try omega.
      rewrite Znth_sublist, <- Hlen, Znth_rotate, Z.add_0_r in Heq by omega.
      eapply NoDup_Znth_inj with (i0 := z)(j := (i - hash k) mod (Zlength m)) in Hwf.
      subst z.
      rewrite Zplus_mod_idemp_l, Z.sub_simpl_r, Z.sub_0_r, Zmod_small in Hi; try omega.
      * destruct Hi; split; auto.
        etransitivity; eauto.
        apply Z_mod_lt; omega.
      * rewrite Zlength_map; auto.
      * rewrite Zlength_map; apply Z_mod_lt; omega.
      * rewrite !Znth_map'; subst k; eauto.
      * rewrite Zlength_rotate; omega.
  - pose proof (index_of'_spec k (rotate m (hash k) 32)) as Hspec'; destruct (index_of' _ _); auto.
    destruct Hspec' as (? & Hrange & Hz & ?); contradiction Hspec.
    rewrite Zlength_rotate in Hrange by omega.
    rewrite <- Hlen, Znth_rotate in Hz by auto.
    rewrite in_map_iff; do 2 eexists; eauto.
    apply Znth_In, Z_mod_lt; omega.
Qed.

Definition get m k := option_map (fun i => snd (Znth i m (0, 0))) (index_of m k).

(* Some of these should probably go up to ghost, or at least atomics. *)
Definition value_of e :=
  match e with
  | Load v => v
  | Store v => v
  | CAS r c w => if eq_dec r c then w else r
  end.

Definition last_value (h : hist) v :=
  (* initial condition *)
  (h = [] /\ v = vint 0) \/
  exists n e, In (n, e) h /\ value_of e = v /\ Forall (fun x => let '(m, _) := x in m <= n)%nat h.

Definition newer (l : hist) t := Forall (fun x => fst x < t)%nat l.

Lemma last_value_new : forall h n e, newer h n ->
  last_value (h ++ [(n, e)]) (value_of e).
Proof.
  right.
  do 3 eexists; [rewrite in_app; simpl; eauto|].
  rewrite Forall_app; repeat constructor.
  eapply Forall_impl; [|eauto]; intros.
  destruct a; simpl in *; omega.
Qed.

Definition ordered_hist h := forall i j (Hi : 0 <= i < j) (Hj : j < Zlength h),
  (fst (Znth i h (O, Store (vint 0))) < fst (Znth j h (O, Store (vint 0))))%nat.

Lemma ordered_cons : forall t e h, ordered_hist ((t, e) :: h) ->
  Forall (fun x => let '(m, _) := x in t < m)%nat h /\ ordered_hist h.
Proof.
  unfold ordered_hist; split.
  - rewrite Forall_forall; intros (?, ?) Hin.
    apply In_Znth with (d := (O, Store (vint 0))) in Hin.
    destruct Hin as (j & ? & Hj).
    exploit (H 0 (j + 1)); try omega.
    { rewrite Zlength_cons; omega. }
    rewrite Znth_0_cons, Znth_pos_cons, Z.add_simpl_r, Hj by omega; auto.
  - intros; exploit (H (i + 1) (j + 1)); try omega.
    { rewrite Zlength_cons; omega. }
    rewrite !Znth_pos_cons, !Z.add_simpl_r by omega; auto.
Qed.

Lemma ordered_last : forall t e h (Hordered : ordered_hist h) (Hin : In (t, e) h)
  (Ht : Forall (fun x => let '(m, _) := x in m <= t)%nat h), last h (O, Store (vint 0)) = (t, e).
Proof.
  induction h; [contradiction | simpl; intros].
  destruct a; apply ordered_cons in Hordered; destruct Hordered as (Ha & ?).
  inversion Ht as [|??? Hp]; subst.
  destruct Hin as [Hin | Hin]; [inv Hin|].
  - destruct h; auto.
    inv Ha; inv Hp; destruct p; omega.
  - rewrite IHh; auto.
    destruct h; auto; contradiction.
Qed.

Definition value_of_hist (h : hist) := value_of (snd (last h (O, Store (vint 0)))).

Lemma ordered_last_value : forall h v (Hordered : ordered_hist h), last_value h v <-> value_of_hist h = v.
Proof.
  unfold last_value, value_of_hist; split; intro.
  - destruct H as [(? & ?) | (? & ? & ? & ? & ?)]; subst; auto.
    erewrite ordered_last; eauto; auto.
  - destruct h; [auto | right].
    destruct (last (p :: h) (O, Store (vint 0))) as (t, e) eqn: Hlast.
    exploit (@app_removelast_last _ (p :: h)); [discriminate | intro Heq].
    rewrite Hlast in Heq.
    exists t; exists e; repeat split; auto.
    + rewrite Heq, in_app; simpl; auto.
    + unfold ordered_hist in Hordered.
      rewrite Forall_forall; intros (?, ?) Hin.
      apply In_Znth with (d := (O, Store (vint 0))) in Hin.
      destruct Hin as (i & ? & Hi).
      rewrite <- Znth_last in Hlast.
      destruct (eq_dec i (Zlength (p :: h) - 1)).
      * subst; rewrite Hlast in Hi; inv Hi; auto.
      * exploit (Hordered i (Zlength (p :: h) - 1)); try omega.
        rewrite Hlast, Hi; simpl; omega.
Qed.

Lemma newer_trans : forall l t1 t2, newer l t1 -> (t1 <= t2)%nat -> newer l t2.
Proof.
  intros.
  eapply Forall_impl, H; simpl; intros; omega.
Qed.

Corollary newer_snoc : forall l t1 e t2, newer l t1 -> (t1 < t2)%nat -> newer (l ++ [(t1, e)]) t2.
Proof.
  unfold newer; intros.
  rewrite Forall_app; split; [|repeat constructor; auto].
  eapply newer_trans; eauto; omega.
Qed.

Lemma ordered_snoc : forall h t e, ordered_hist h -> newer h t -> ordered_hist (h ++ [(t, e)]).
Proof.
  repeat intro.
  rewrite Zlength_app, Zlength_cons, Zlength_nil in Hj.
  rewrite app_Znth1 by omega.
  destruct (eq_dec j (Zlength h)).
  - rewrite Znth_app1; auto.
    apply Forall_Znth; auto; omega.
  - specialize (H i j).
    rewrite app_Znth1 by omega; apply H; auto; omega.
Qed.

Definition int_op e :=
  match e with
  | Load v | Store v => tc_val tint v
  | CAS r c w => tc_val tint r /\ tc_val tint c /\ tc_val tint w
  end.

(* Once set, a key is never reset. *)
Definition k_R (h : list hist_el) (v : val) := !!(Forall int_op h /\
  forall e, In e h -> value_of e <> vint 0 -> v = value_of e) && emp.

Definition v_R (h : list hist_el) (v : val) := emp.

Definition atomic_entry sh p := !!(field_compatible tentry [] p) && EX lkey : val, EX lval : val,
  field_at sh tentry [StructField _lkey] lkey p *
  atomic_loc sh lkey (field_address tentry [StructField _key] p) (vint 0) Tsh k_R *
  field_at sh tentry [StructField _lvalue] lval p *
  atomic_loc sh lval (field_address tentry [StructField _value] p) (vint 0) Tsh v_R.

(* Entries are no longer consecutive. *)
Definition wf_hists h := Forall (fun x => (ordered_hist (fst x) /\ Forall int_op (map snd (fst x))) /\
  (ordered_hist (snd x) /\ Forall int_op (map snd (snd x)))) h.

Definition make_int v := match v with Vint i => Int.signed i | _ => 0 end.

Lemma make_int_spec : forall v, tc_val tint v -> vint (make_int v) = v.
Proof.
  destruct v; try contradiction; simpl.
  rewrite Int.repr_signed; auto.
Qed.

Lemma make_int_repable : forall v, repable_signed (make_int v).
Proof.
  destruct v; simpl; try (split; computable).
  apply Int.signed_range.
Qed.

Definition make_map h :=
  map (fun hs => (make_int (value_of_hist (fst hs)), make_int (value_of_hist (snd hs)))) h.

Lemma make_map_eq : forall h h', Forall2 (fun a b => value_of_hist (fst a) = value_of_hist (fst b) /\
  value_of_hist (snd a) = value_of_hist (snd b)) h h' -> make_map h = make_map h'.
Proof.
  induction 1; auto; simpl.
  destruct x, y; simpl in *.
  destruct H as (-> & ->); rewrite IHForall2; auto.
Qed.

Lemma int_op_value : forall e, int_op e -> tc_val tint (value_of e).
Proof.
  destruct e; auto; simpl.
  intros (? & ? & ?); destruct (eq_dec r c); auto.
Qed.

Corollary int_op_value_of_hist : forall h, Forall int_op (map snd h) -> tc_val tint (value_of_hist h).
Proof.
  intros; unfold value_of_hist.
  apply Forall_last; simpl; auto.
  rewrite Forall_map in H; eapply Forall_impl; [|eauto].
  simpl; intros; apply int_op_value; auto.
Qed.

Lemma make_map_no_key : forall h k (Hout : Forall (fun x => make_int (value_of_hist (fst x)) <> k) h),
  Forall (fun x => fst x <> k) (make_map h).
Proof.
  induction h; simpl; auto; intros.
  destruct a.
  inv Hout.
  constructor; auto.
Qed.

Definition failed_CAS k (a b : hist * hist) := exists t r, newer (fst a) t /\
  (fst b = fst a ++ [(t, Load (Vint r))] \/
   exists t1, (t < t1)%nat /\ fst b = fst a ++ [(t, Load (vint 0)); (t1, CAS (Vint r) (vint 0) (vint k))]) /\
  r <> Int.zero /\ r <> Int.repr k /\ snd b = snd a /\
  (let v := value_of_hist (fst a) in v <> vint 0 -> v = Vint r).

Definition set_item_trace (h : list (hist * hist)) k v i h' := Zlength h' = Zlength h /\
  0 <= i < Zlength h /\
  (let '(hk, hv) := Znth i h ([], []) in exists t r tv, newer hk t /\ newer hv tv /\
     (fst (Znth i h' ([], [])) = hk ++ [(t, Load (vint k))] /\ r = vint k \/
      exists t1, (t < t1)%nat /\
        fst (Znth i h' ([], [])) = hk ++ [(t, Load (vint 0)); (t1, CAS r (vint 0) (vint k))] /\
        (r = vint 0 \/ r = vint k)) /\
     snd (Znth i h' ([], [])) = hv ++ [(tv, Store (vint v))] /\
     (let v := value_of_hist hk in v <> vint 0 -> v = r)) /\
  forall j, (In j (indices (hash k) i) -> failed_CAS k (Znth j h ([], [])) (Znth j h' ([], []))) /\
    (~In j (indices (hash k) i) -> j <> i -> Znth j h' ([], []) = Znth j h ([], [])).

(* up *)
Lemma app_cons_assoc : forall {A} l1 (x : A) l2, l1 ++ x :: l2 = (l1 ++ [x]) ++ l2.
Proof.
  intros; rewrite <- app_assoc; auto.
Qed.

Definition map_incl (m m' : list (Z * Z)) := forall k v i, k <> 0 -> Znth i m (0, 0) = (k, v) ->
  Znth i m' (0, 0) = (k, v).

(* up *)
Lemma Forall_forall_Znth : forall {A} (P : A -> Prop) l d,
  Forall P l <-> forall i, 0 <= i < Zlength l -> P (Znth i l d).
Proof.
  split; intros; [apply Forall_Znth; auto|].
  induction l; auto.
  rewrite Zlength_cons in *.
  constructor.
  - specialize (H 0); rewrite Znth_0_cons in H; apply H.
    pose proof (Zlength_nonneg l); omega.
  - apply IHl; intros.
    specialize (H (i + 1)).
    rewrite Znth_pos_cons, Z.add_simpl_r in H by omega.
    apply H; omega.
Qed.

Lemma set_item_trace_map : forall h k v i h' (Hwf : wf_hists h) (Hm : wf_map (make_map h))
  (Htrace : set_item_trace h k v i h')
  (Hk : k <> 0) (Hrepk : repable_signed k) (Hrepv : repable_signed v),
  wf_hists h' /\ let m' := make_map (upd_Znth i h' (Znth i h ([], []))) in
    map_incl (make_map h) m' /\ make_map h' = upd_Znth i m' (k, v) /\ wf_map (make_map h').
Proof.
  intros.
  destruct Htrace as (Hlen & Hbounds & Hi & Hrest).
  destruct (Znth i h ([], [])) as (hk, hv) eqn: Hhi.
  destruct Hi as (t & r & tv & Ht & Htv & Hi1 & Hi2 & Hr0).
  assert (i <= Zlength h') by (rewrite Hlen; destruct Hbounds; apply Z.lt_le_incl; auto).
  assert (0 <= i + 1 <= Zlength h').
  { rewrite Hlen; destruct Hbounds; split; [|rewrite <- lt_le_1]; auto; omega. }
  assert (vint k <> vint 0).
  { intro; contradiction Hk; apply repr_inj_signed; auto.
    { split; computable. }
    { congruence. }}
  assert (r = vint 0 \/ r = vint k) as Hr.
  { destruct Hi1 as [(? & ?) | (? & ? & ? & ?)]; auto. }
  assert ((if eq_dec r (vint 0) then vint k else r) = vint k) as Hif.
  { if_tac; auto.
    destruct Hr; [absurd (r = vint 0)|]; auto. }
  assert (value_of_hist (fst (Znth i h' ([], []))) = vint k) as Hk'.
  { destruct Hi1 as [(-> & ?) | (? & ? & -> & ?)].
    - unfold value_of_hist; rewrite last_snoc; auto.
    - rewrite app_cons_assoc; unfold value_of_hist; rewrite last_snoc; auto. }
  assert (wf_hists h') as Hwf'; [|split; auto; split; [|split]].
  - unfold wf_hists; rewrite Forall_forall_Znth; intros j ?.
    apply (Forall_Znth _ _ j ([], [])) in Hwf; [destruct Hwf as ((? & ?) & ? & ?) | omega].
    destruct (eq_dec j i); [|specialize (Hrest j); destruct (in_dec Z_eq_dec j (indices (hash k) i))].
    + subst; rewrite Hhi in *.
      split; [|rewrite Hi2, map_app, Forall_app; repeat constructor; auto; apply ordered_snoc; auto].
      destruct Hi1 as [(-> & _) | (? & ? & -> & _)]; rewrite map_app, Forall_app; repeat constructor;
        auto; try (apply ordered_snoc; auto).
      * rewrite app_cons_assoc; apply ordered_snoc; [apply ordered_snoc; auto|].
        apply newer_snoc; auto.
      * destruct Hr; subst; simpl; auto.
    + destruct Hrest as ((? & ? & ? & Hcase & ? & ? & -> & ?) & _); auto; simpl in *.
      split; auto.
      destruct Hcase as [-> | (? & ? & ->)]; rewrite map_app, Forall_app; repeat constructor; auto.
      * apply ordered_snoc; auto.
      * rewrite app_cons_assoc; apply ordered_snoc; [apply ordered_snoc; auto|].
        apply newer_snoc; auto.
    + destruct Hrest as (_ & ->); auto.
  - intros k0 v0 j Hk0 Hj.
    exploit (Znth_inbounds j (make_map h) (0, 0)).
    { rewrite Hj; intro X; inv X; contradiction Hk0; auto. }
    intro; unfold make_map in *; rewrite <- upd_Znth_map.
    rewrite Zlength_map in *.
    rewrite Znth_map with (d' := ([], [])) in Hj by auto; inv Hj.
    destruct (eq_dec j i); [subst; rewrite upd_Znth_same, Hhi; auto | rewrite upd_Znth_diff];
      rewrite ?Zlength_map in *; auto; try omega.
    rewrite Znth_map with (d' := ([], [])) by omega.
    specialize (Hrest j); destruct (in_dec Z_eq_dec j (indices (hash k) i));
      [|destruct Hrest as (_ & ->); auto].
    destruct Hrest as ((? & r1 & ? & Hcase & ? & ? & -> & Heq) & _); auto; simpl in *.
    assert (value_of_hist (fst (Znth j h ([], []))) <> vint 0).
    { intro X; rewrite X in Hk0; contradiction Hk0; auto. }
    destruct Hcase as [-> | (? & ? & ->)].
    + unfold value_of_hist at 1; rewrite last_snoc, Heq; auto.
    + rewrite app_cons_assoc; unfold value_of_hist at 1; rewrite last_snoc, Heq; auto; simpl.
      destruct (eq_dec (Vint r1) (vint 0)); auto.
      absurd (r1 = Int.zero); auto; inv e; auto.
  - assert (0 <= i < Zlength h') by (rewrite Hlen; auto).
    unfold make_map; rewrite <- upd_Znth_map, upd_Znth_twice by (rewrite Zlength_map; auto).
    apply list_Znth_eq' with (d := (0, 0)).
    { rewrite upd_Znth_Zlength; auto.
      rewrite Zlength_map; auto. }
    rewrite Zlength_map; intros.
    destruct (eq_dec j i); [subst; rewrite upd_Znth_same; auto | rewrite upd_Znth_diff];
      rewrite ?Zlength_map; auto.
    rewrite Znth_map with (d' := ([], [])) by omega.
    unfold value_of_hist at 2; rewrite Hi2, last_snoc; simpl.
    rewrite Int.signed_repr by auto.
    destruct Hi1 as [(-> & ?) | (? & ? & -> & ?)].
    + unfold value_of_hist; rewrite last_snoc; simpl.
      rewrite Int.signed_repr; auto.
    + unfold value_of_hist; rewrite app_cons_assoc, last_snoc; simpl.
      rewrite Hif; simpl.
      rewrite Int.signed_repr; auto.
  - repeat intro.
Qed.

(* What can a thread know?
   At least certain keys exist, and whatever it did last took effect.
   It can even rely on the indices of known keys. *)
Definition set_item_spec :=
 DECLARE _set_item
  WITH key : Z, value : Z, p : val, sh : share, entries : list val, h : list (hist * hist)
  PRE [ _key OF tint, _value OF tint ]
   PROP (repable_signed key; repable_signed value; readable_share sh; key <> 0; Forall isptr entries;
         Zlength h = 32; wf_hists h)
   LOCAL (temp _key (vint key); temp _value (vint value); gvar _m_entries p)
   SEP (data_at sh (tarray (tptr tentry) 32) entries p;
        fold_right sepcon emp (map (atomic_entry sh) entries);
        entry_hists entries h)
  POST [ tvoid ]
   EX i0 : Z, EX i : Z, EX h' : list (hist * hist),
   PROP (set_item_trace h key value i0 i h')
   LOCAL ()
   SEP (data_at sh (tarray (tptr tentry) 32) entries p;
        fold_right sepcon emp (map (atomic_entry sh) entries);
        entry_hists entries h').
(* set_item_trace_map describes the properties on the resulting map. *)

Lemma index_of_iff_out : forall m k, index_of m k = None <-> ~In k (map fst m).
Proof.
  split; intro.
  - induction m; auto; simpl in *.
    destruct a.
    destruct (eq_dec z k); [discriminate|].
    destruct (index_of m k); [discriminate|].
    intros [? | ?]; auto.
    contradiction IHm.
  - apply index_of_out.
    rewrite Forall_forall; repeat intro; contradiction H.
    rewrite in_map_iff; eauto.
Qed.

Corollary get_fail_iff : forall m k, get m k = None <-> ~In k (map fst m).
Proof.
  intros; unfold get; rewrite <- index_of_iff_out.
  destruct (index_of m k); simpl; split; auto; discriminate.
Qed.

Definition failed_load k (a b : hist * hist) := exists t r, newer (fst a) t /\
  fst b = fst a ++ [(t, Load (Vint r))] /\ r <> Int.zero /\ r <> Int.repr k /\ snd b = snd a /\
  (let v := value_of_hist (fst a) in v <> vint 0 -> v = Vint r).

(* get_item can return 0 in two cases: if the key is not in the map, or if its value is 0.
   In correct use, the latter should only occur if the value has not been initialized.
   Conceptually, this is still linearizable because we could have just checked before the key was added,
   but at a finer-grained level we can tell the difference from the history, so we might as well keep
   this information. *)
Definition get_item_trace (h : list (hist * hist)) k v i0 i h' := Zlength h' = Zlength h /\
  0 <= i < Zlength h /\
  (let '(hk, hv) := Znth i h ([], []) in exists t r, newer hk t /\
     fst (Znth i h' ([], [])) = hk ++ [(t, Load (vint r))] /\
     (v = 0 /\ r = 0 /\ snd (Znth i h' ([], [])) = hv \/
      r = k /\ exists tv, Forall (fun x => fst x < tv)%nat hv /\
        snd (Znth i h' ([], [])) = hv ++ [(tv, Load (vint v))]) /\
    (let v := value_of_hist hk in v <> vint 0 -> v = vint r)) /\
  forall j, (In j (indices i0 i) -> failed_load k (Znth j h ([], [])) (Znth j h' ([], []))) /\
    (~In j (indices i0 i) -> j <> i -> Znth j h' ([], []) = Znth j h ([], [])).

Lemma Znth_make_map : forall d h i (Hi : 0 <= i < Zlength h)
  (Hnz : Forall (fun x => value_of_hist (fst x) <> vint 0) (sublist 0 (i + 1) h))
  (Hint : Forall (fun x => Forall int_op (map snd (fst x))) (sublist 0 (i + 1) h)),
  Znth i (make_map h) d = (make_int (value_of_hist (fst (Znth i h ([], [])))),
                           make_int (value_of_hist (snd (Znth i h ([], []))))).
Proof.
  induction h; simpl; intros.
  { rewrite Zlength_nil in *; omega. }
  destruct a.
  rewrite Zlength_cons in *.
  rewrite sublist_0_cons, Z.add_simpl_r in Hnz, Hint by omega.
  inv Hnz; inv Hint.
  exploit int_op_value_of_hist; eauto; intro; simpl in *.
  destruct (value_of_hist l) eqn: Hfst; try contradiction; simpl.
  if_tac; [absurd (Vint i0 = vint 0); auto; f_equal; apply signed_inj; auto|].
  destruct (eq_dec i 0).
  - subst; rewrite !Znth_0_cons; simpl; auto.
    rewrite Hfst; auto.
  - rewrite !Znth_pos_cons by omega; apply IHh; rewrite ?Z.sub_simpl_r; auto; omega.
Qed.

Lemma get_item_trace_map : forall h k v i h' l (Hwf : wf_hists h l) (Htrace : get_item_trace h k v i h')
  (Hk : k <> 0) (Hrepk : repable_signed k) (Hrepv : repable_signed v),
  match get (make_map h') k with
  | Some v' => v' = v /\ wf_hists h' (Z.max (i + 1) l) /\ incl (set (make_map h) k v) (make_map h')
  | None => l <= i /\ wf_hists h' i /\ v = 0 /\ incl (make_map h) (make_map h') end.
Proof.
  intros.
  destruct Htrace as (Hbounds & Hfail & Hi & Hrest).
  destruct (Znth i h ([], [])) as (hk, hv) eqn: Hhi.
  destruct Hi as (t & r & Ht & Hi1 & Hi2 & Hr0).
  assert (Zlength h' = Zlength h) as Hlen.
  { exploit (Znth_inbounds i h' ([], [])).
    { destruct (Znth i h' ([], [])) as (hk', hv'); intro X; inv X.
      apply app_cons_not_nil in Hi1; auto. }
    intro.
    assert (Zlength (sublist (i + 1) (Zlength h) h) = Zlength (sublist (i + 1) (Zlength h') h')) as Heq
      by (rewrite Hrest; auto).
    rewrite !Zlength_sublist in Heq; omega. }
  assert (i <= Zlength h') by (rewrite Hlen; destruct Hbounds; apply Z.lt_le_incl; auto).
  assert (0 <= i + 1 <= Zlength h').
  { rewrite Hlen; destruct Hbounds; split; [|rewrite <- lt_le_1]; auto; omega. }
  destruct Hwf as (Hwf & ? & Hl1 & Hl2).
  assert (vint k <> vint 0).
  { intro; contradiction Hk; apply repr_inj_signed; auto.
    { split; computable. }
    { congruence. }}
  assert (Forall (fun x => value_of_hist (fst x) <> vint 0) (sublist 0 i h')).
  { rewrite Forall_forall; intros (?, ?) Hin.
    exploit (Forall2_In_r (failed_load k)); eauto.
    intros ((?, ?) & ? & ? & r1 & ? & ? & ? & ? & ? & ?); simpl in *; subst.
    unfold value_of_hist; rewrite last_snoc; simpl.
    intro X; absurd (r1 = Int.zero); auto; inv X; auto. }
  assert (h' = sublist 0 i h' ++ Znth i h' ([], []) :: sublist (i + 1) (Zlength h') h') as Hh'.
  { rewrite <- sublist_next, sublist_rejoin, sublist_same; auto; try omega; rewrite Hlen; auto. }
  assert (Forall (fun x => (ordered_hist (fst x) /\ Forall int_op (map snd (fst x))) /\ ordered_hist (snd x) /\
    Forall int_op (map snd (snd x))) h') as Hwf'.
  { rewrite Hh'; clear Hh'; rewrite Forall_app; split; [|constructor].
    - eapply Forall_Forall2; try apply Hfail; [apply Forall_sublist; auto|].
      intros (?, ?) (?, ?) ((? & ?) & ? & ?) (? & ? & ? & ? & ? & ? & ? & ?); simpl in *; subst.
      rewrite map_app, Forall_app; repeat constructor; auto; apply ordered_snoc; auto.
    - eapply Forall_Znth with (i0 := i) in Hwf; auto.
      rewrite Hhi in Hwf; destruct Hwf as ((? & ?) & ? & ?).
      rewrite Hi1; split.
      { split; [apply ordered_snoc | rewrite map_app, Forall_app; repeat constructor]; auto. }
      destruct Hi2 as [(? & ? & ->) | (? & ? & ? & ->)]; rewrite ?map_app, ?Forall_app;
        repeat constructor; auto; try (apply ordered_snoc; auto).
    - rewrite <- Hrest; apply Forall_sublist; auto. }
  assert (Forall (fun x => Forall int_op (map snd (fst x))) (sublist 0 i h')).
  { eapply Forall_sublist, Forall_impl, Hwf'; tauto. }
  assert (Forall (fun x => make_int (value_of_hist (fst x)) <> k) (sublist 0 i h')) as Hmiss.
  { clear Hh'; rewrite Forall_forall; intros (hk', hv') Hin.
    exploit (Forall2_In_r _ (hk', hv') _ _ Hfail); auto.
    intros (? & ? & ? & r1 & ? & Heqi & ? & ? & ? & ?); subst.
    unfold value_of_hist; rewrite Heqi, last_snoc; simpl.
    intro; absurd (r1 = Int.repr k); subst; auto.
    rewrite Int.repr_signed; auto. }
  unfold get; destruct (index_of (make_map h') k) eqn: Hindex; simpl.
  - rewrite Hh', make_map_app, index_of_app, index_of_out in Hindex
      by (auto; apply make_map_no_key; auto).
    simpl in Hindex.
    destruct (Znth i h' ([], [])) as (hk', hv') eqn: Hhi'; simpl in *; subst hk'.
    unfold value_of_hist in Hindex; rewrite last_snoc in Hindex; simpl in Hindex.
    destruct Hi2 as [(? & ? & ?) | (? & tv & ? & ?)]; subst r hv'; [discriminate|].
    rewrite Int.signed_repr in Hindex by auto.
    destruct (eq_dec k 0); [contradiction Hk; auto|].
    simpl in Hindex.
    rewrite eq_dec_refl in Hindex; simpl in Hindex.
    inversion Hindex; subst z.
    rewrite make_map_length, Zlength_sublist, Z.sub_simpl_r by (auto; omega).
    assert (0 <= Z.max (i + 1) l <= Zlength h' /\
      Forall (fun x => value_of_hist (fst x) <> vint 0) (sublist 0 (Z.max (i + 1) l) h') /\
      Forall (fun x => value_of_hist (fst x) = vint 0) (sublist (Z.max (i + 1) l) (Zlength h') h'))
      as (? & Hl1' & Hl2'); [|split; [|split; [split; auto|]]].
    + assert (0 <= Z.max (i + 1) l <= Zlength h'); [|split; auto].
      { destruct (Z.max_spec (i + 1) l) as [(? & ->) | (? & ->)]; auto; omega. }
      split; [|apply Forall_suffix_max with (l1 := h); auto; omega].
      rewrite Hh'; clear Hh'.
      assert (Zlength h' <= i - 0 + Z.succ (Zlength h' - (i + 1))) by omega.
      assert (0 <= Zlength h' - i) by omega.
      destruct (Z.max_spec (i + 1) l) as [(? & ->) | (? & ->)].
      * rewrite !sublist_app; rewrite ?Zlength_cons, ?Zlength_sublist; auto; try omega.
        rewrite Z.min_l, Z.min_r, Z.max_r, Z.max_l by omega.
        rewrite !Z.sub_0_r.
        rewrite sublist_sublist, !Z.add_0_r by omega.
        rewrite Forall_app; split; auto.
        rewrite sublist_0_cons by omega.
        constructor; [unfold value_of_hist; simpl; rewrite last_snoc; auto|].
        rewrite sublist_sublist by omega.
        rewrite <- Z.sub_add_distr, Z.sub_simpl_r.
        rewrite Z.add_0_l, sublist_parts2; try omega.
        rewrite <- Hrest.
        rewrite <- sublist_parts2 by omega.
        rewrite sublist_parts1 by omega; apply Forall_sublist; auto.
      * rewrite !sublist_app; rewrite ?Zlength_cons, ?Zlength_sublist; auto; try omega.
        rewrite !Z.sub_0_r, Z.min_l, Z.min_r, Z.max_r, Z.max_l; auto; try omega.
        rewrite Z.add_simpl_l.
        rewrite sublist_same, sublist_len_1 with (d := ([], [])), Znth_0_cons;
          rewrite ?Zlength_cons, ?Zlength_sublist; auto; try omega; simpl.
        rewrite Forall_app; split; auto.
        constructor; auto; unfold value_of_hist; simpl; rewrite last_snoc; auto.
    + rewrite Znth_make_map, Hhi'; simpl.
      unfold value_of_hist; rewrite last_snoc; simpl.
      apply Int.signed_repr; auto.
      { omega. }
      { rewrite sublist_split with (mid := i), Forall_app by omega; split; auto.
        erewrite sublist_len_1, Hhi' by omega; repeat constructor; simpl.
        unfold value_of_hist; rewrite last_snoc; auto. }
      { eapply Forall_sublist, Forall_impl, Hwf'; tauto. }
    + unfold set.
      rewrite Hh'; clear Hh'.
      rewrite make_map_app by auto; simpl.
      unfold value_of_hist; rewrite !last_snoc; simpl.
      rewrite !Int.signed_repr by auto.
      destruct (eq_dec k 0); [contradiction Hk; auto|].
      assert (0 <= Z.min i l <= Zlength h) as (? & ?).
      { split; [rewrite Z.min_glb_iff | rewrite Z.min_le_iff]; auto; omega. }
      replace h with (sublist 0 (Z.min i l) h ++ sublist (Z.min i l) (Zlength h) h)
        by (rewrite sublist_rejoin, sublist_same; auto; omega).
      assert (Forall (fun x => value_of_hist (fst x) <> vint 0) (sublist 0 (Z.min i l) h)).
      { rewrite <- sublist_prefix; apply Forall_sublist; auto. }
      assert (Forall (fun x => Forall int_op (map snd (fst x))) (sublist 0 (Z.min i l) h)).
      { eapply Forall_sublist, Forall_impl, Hwf; tauto. }
      rewrite make_map_app, index_of_app, index_of_out; auto.
      assert (incl (make_map (sublist 0 (Z.min i l) h)) (make_map (sublist 0 (Z.min i l) h'))).
      { erewrite make_map_eq; [apply incl_refl|].
        rewrite Forall2_eq_upto with (d1 := ([] : hist, [] : hist))(d2 := ([] : hist, [] : hist)).
        split; [rewrite !Zlength_sublist; auto; omega|].
        rewrite Forall_forall; intros ? Hin.
        rewrite In_upto, Z2Nat.id in Hin by (apply Zlength_nonneg).
        assert (value_of_hist (fst (Znth x (sublist 0 (Z.min i l) h) ([], []))) <> vint 0) as Hnz.
        { apply Forall_Znth; auto. }
        rewrite Zlength_sublist, Z.sub_0_r in Hin by (auto; omega).
        assert (x < i).
        { destruct Hin; eapply Z.lt_le_trans; eauto.
          apply Z.le_min_l. }
        exploit (Forall2_Znth _ _ _ ([], []) ([], []) Hfail x); auto.
        { rewrite Zlength_sublist; omega. }
        intros (? & r1 & ? & Heq1 & ? & ? & Heq2 & Hv).
        rewrite !Znth_sublist, Z.add_0_r in Heq1, Heq2, Hv, Hnz; auto; try omega.
        rewrite !Znth_sublist, Z.add_0_r in Heq1, Heq2 by omega.
        rewrite !Znth_sublist, Z.add_0_r by omega.
        rewrite Heq1, Heq2; simpl; split; auto.
        unfold value_of_hist in *; rewrite last_snoc; simpl.
        destruct (eq_dec (Vint r1) (vint 0)); [absurd (r1 = Int.zero); auto; inv e; auto | auto]. }
      destruct (Z.min_spec i l) as [(? & Hmin) | (? & Hmin)]; rewrite Hmin in *.
      * erewrite sublist_next with (i0 := i) by omega.
        rewrite Hhi; simpl.
        rewrite Hr0; simpl.
        rewrite Int.signed_repr by auto; simpl.
        destruct (eq_dec k 0); [contradiction Hk; auto | simpl].
        rewrite eq_dec_refl; simpl.
        rewrite Z.add_0_r, upd_Znth_app2; rewrite make_map_length; auto.
        rewrite Zminus_diag, upd_Znth0, sublist_1_cons, Zlength_cons.
        unfold Z.succ; rewrite Z.add_simpl_r, sublist_same with (hi := Zlength _) by auto.
        rewrite Hrest; apply incl_app; [apply incl_appl; auto | apply incl_appr, incl_refl].
        { pose proof (Zlength_nonneg
            ((k, make_int (value_of_hist hv)) :: make_map (sublist (i + 1) (Zlength h) h))); omega. }
        { eapply Forall_Znth with (i0 := i) in Hl1; [|rewrite Zlength_sublist; omega].
          rewrite Znth_sublist, Z.add_0_r, Hhi in Hl1 by omega; auto. }
      * rewrite make_map_nil with (h := sublist l _ _), app_nil_r; auto; simpl.
        apply incl_app; [apply incl_appl | apply incl_appr; constructor; simpl in *; tauto].
        rewrite sublist_split with (mid := l)(hi := i) by omega.
        rewrite make_map_app.
        apply incl_appl; auto.
        { replace l with (Z.min l (Z.max (i + 1) l)).
          rewrite <- sublist_prefix; apply Forall_sublist; auto.
          { apply Z.min_l, Zmax_bound_r, Z.le_refl. } }
        { eapply Forall_sublist, Forall_impl, Hwf'; tauto. }
      * apply make_map_no_key.
        rewrite Forall_forall; intros ? Hin.
        rewrite Forall_forall in Hl1; specialize (Hl1 x).
        exploit (Forall2_In_l _ x _ _ Hfail).
        { rewrite Z.min_comm, <- sublist_prefix in Hin; eapply sublist_In; eauto. }
        intros (? & ? & ? & r1 & ? & ? & ? & ? & ? & Heq); simpl in *; subst.
        rewrite Heq; simpl.
        intro; absurd (r1 = Int.repr k); auto.
        apply signed_inj; auto.
        rewrite Int.signed_repr; auto.
        { apply Hl1.
          rewrite <- sublist_prefix in Hin; eapply sublist_In; eauto. }
  - rewrite index_of_iff_out in Hindex.
    destruct Hi2 as [(? & ? & Hi2) | (? & ? & ? & Hi2)]; subst r.
    clear Hh'.
    assert (value_of_hist hk = vint 0) as Hz.
    { destruct (eq_dec (value_of_hist hk) (vint 0)); auto. }
    destruct (zlt i l).
    { eapply Forall_Znth with (i0 := i) in Hl1; [|rewrite Zlength_sublist; omega].
      rewrite Znth_sublist, Z.add_0_r, Hhi in Hl1 by omega; contradiction Hl1. }
    split; [omega|].
    assert (0 <= i <= Zlength h' /\
      Forall (fun x => value_of_hist (fst x) <> vint 0) (sublist 0 i h') /\
      Forall (fun x => value_of_hist (fst x) = vint 0) (sublist i (Zlength h') h'))
      as (? & Hl1' & Hl2'); [|split; split; auto].
    + split; [omega|]; split.
      * rewrite Forall_forall; intros.
        exploit (Forall2_In_r (failed_load k)); eauto.
        intros ((?, ?) & ? & ? & r1 & ? & -> & ? & ? & ? & ?); simpl in *; subst.
        unfold value_of_hist; rewrite last_snoc; simpl.
        intro X; absurd (r1 = Int.zero); auto; inv X; auto.
      * erewrite sublist_next by omega; constructor;
          [rewrite Hi1; unfold value_of_hist; rewrite last_snoc; auto|].
        rewrite <- Hrest.
        replace (i + 1) with (i + 1 - l + l) by (apply Z.sub_simpl_r).
        rewrite <- sublist_suffix by omega; apply Forall_sublist; auto.
    + replace h with (sublist 0 l h ++ sublist l (Zlength h) h)
        by (rewrite sublist_rejoin, sublist_same; auto; omega).
      replace h' with (sublist 0 l h' ++ sublist l (Zlength h') h')
        by (rewrite sublist_rejoin, sublist_same; auto; omega).
      rewrite make_map_drop, make_map_app; auto.
      apply incl_appl; erewrite make_map_eq; [apply incl_refl|].
      rewrite Forall2_eq_upto with (d1 := ([] : hist, [] : hist))(d2 := ([] : hist, [] : hist)).
      split; [rewrite !Zlength_sublist; auto; omega|].
      rewrite Forall_forall; intros ? Hin.
      rewrite In_upto, Z2Nat.id in Hin by (apply Zlength_nonneg).
      assert (value_of_hist (fst (Znth x (sublist 0 l h) ([], []))) <> vint 0) as Hnz.
      { apply Forall_Znth; auto. }
      rewrite Zlength_sublist, Z.sub_0_r in Hin by (auto; omega).
      assert (x < i) by omega.
      exploit (Forall2_Znth _ _ _ ([], []) ([], []) Hfail x); auto.
      { rewrite Zlength_sublist; omega. }
      intros (? & r1 & ? & Heq1 & ? & ? & Heq2 & Hv).
      rewrite !Znth_sublist, Z.add_0_r in Heq1, Heq2, Hv, Hnz; auto; try omega.
      rewrite !Znth_sublist, Z.add_0_r in Heq1, Heq2 by omega.
      rewrite !Znth_sublist, Z.add_0_r by omega.
      rewrite Heq1, Heq2; simpl; split; auto.
      unfold value_of_hist at 2; rewrite last_snoc; auto.
      { replace l with (Z.min l i) by (apply Z.min_l; omega).
        rewrite <- sublist_prefix; apply Forall_sublist; auto. }
      { eapply Forall_sublist, Forall_impl, Hwf'; tauto. }
    + contradiction Hindex.
      assert (Forall (fun x => value_of_hist (fst x) <> vint 0) (sublist 0 i h' ++ [Znth i h' ([], [])])).
      { rewrite Forall_app; split; auto; repeat constructor.
        rewrite Hi1; unfold value_of_hist; rewrite last_snoc; auto. }
      assert (Forall (fun x => Forall int_op (map snd (fst x))) (sublist 0 (i + 1) h')) as Hints.
      { eapply Forall_sublist, Forall_impl, Hwf'; tauto. }
      rewrite in_map_iff; exists (Znth i (make_map h') (0, 0)); split.
      * rewrite Znth_make_map; auto; simpl.
        rewrite Hi1; unfold value_of_hist; rewrite last_snoc; simpl.
        rewrite Int.signed_repr; auto.
        { omega. }
        { erewrite sublist_split with (mid := i), sublist_len_1 by omega; eauto. }
      * apply Znth_In.
        rewrite Hh'.
        rewrite app_cons_assoc.
        erewrite sublist_split with (mid := i), sublist_len_1 in Hints by omega.
        rewrite make_map_app, Zlength_app, make_map_length, Zlength_app, Zlength_sublist,
          Zlength_cons, Zlength_nil by (eauto; omega).
        pose proof (Zlength_nonneg (make_map (sublist (i + 1) (Zlength h') h'))); omega.
Qed.

(* Read the most recently written value. *)
Definition get_item_spec :=
 DECLARE _get_item
  WITH key : Z, p : val, sh : share, entries : list val, h : list (hist * hist), l : Z
  PRE [ _key OF tint, _value OF tint ]
   PROP (repable_signed key; readable_share sh; key <> 0; Forall isptr entries; Zlength h = 32; wf_hists h l)
   LOCAL (temp _key (vint key); gvar _m_entries p)
   SEP (data_at sh (tarray (tptr tentry) 32) entries p;
        fold_right sepcon emp (map (atomic_entry sh) entries);
        entry_hists entries h)
  POST [ tint ]
   EX value : Z, EX i : Z, EX h' : list (hist * hist),
   PROP (repable_signed value; get_item_trace h key value i h')
   LOCAL (temp ret_temp (vint value))
   SEP (data_at sh (tarray (tptr tentry) 32) entries p;
        fold_right sepcon emp (map (atomic_entry sh) entries);
        entry_hists entries h').

Definition Gprog : funspecs := ltac:(with_library prog [surely_malloc_spec; atomic_CAS_spec; atomic_load_spec;
  atomic_store_spec; integer_hash_spec; set_item_spec; get_item_spec]).

Lemma body_surely_malloc: semax_body Vprog Gprog f_surely_malloc surely_malloc_spec.
Proof.
  start_function.
  forward_call n.
  Intros p.
  forward_if
  (PROP ( )
   LOCAL (temp _p p)
   SEP (malloc_token Tsh n p * memory_block Tsh n p)).
  - if_tac; entailer!.
  - forward_call tt.
    contradiction.
  - if_tac.
    + forward. subst p. discriminate.
    + Intros. forward. entailer!.
  - forward. Exists p; entailer!.
Qed.

Lemma body_integer_hash: semax_body Vprog Gprog f_integer_hash integer_hash_spec.
Proof.
  start_function.
  forward.
  Exists (i * 654435761)%Z; entailer!.
Qed.

Opaque upto.

Ltac cancel_for_forward_call ::= repeat (rewrite ?sepcon_andp_prop', ?sepcon_andp_prop);
  repeat (apply andp_right; [auto; apply prop_right; auto|]); fast_cancel.

Ltac entailer_for_return ::= go_lower; entailer'.

Lemma apply_int_ops : forall v h i (Hv : verif_atomics.apply_hist (Vint i) h = Some v)
  (Hints : Forall int_op h), tc_val tint v.
Proof.
  induction h; simpl; intros.
  - inv Hv; eauto.
  - inversion Hints as [|?? Ha]; subst.
    destruct a.
    + destruct (eq_dec v0 (Vint i)); [eapply IHh; eauto | discriminate].
    + destruct v0; try contradiction; eapply IHh; eauto.
    + destruct (eq_dec r (Vint i)); [|discriminate].
      destruct Ha as (? & ? & ?).
      destruct w; try contradiction.
      destruct (eq_dec c (Vint i)); eapply IHh; eauto.
Qed.

Lemma failed_CAS_fst : forall v h h', Forall2 (failed_CAS v) h h' -> map snd h' = map snd h.
Proof.
  induction 1; auto.
  destruct H as (? & ? & ? & ? & ? & ? & ? & ?); simpl; f_equal; auto.
Qed.

Lemma body_set_item : semax_body Vprog Gprog f_set_item set_item_spec.
Proof.
  start_function.
  forward_call key.
  Intro i'.
  eapply semax_pre with (P' := EX i : Z, EX i1 : Z, EX h' : list (hist * hist),
    PROP (i1 mod 32 = (i' + i) mod 32; 0 <= i < 32;
          forall j, if in_dec Z_eq_dec j (map (fun x => (i' + x) mod 32) (upto (Z.to_nat i)))
            then failed_CAS key (Znth j h ([], [])) (Znth j h' ([], []))
            else Znth j h' ([], []) = Znth j h ([], []))
    LOCAL (temp _idx (vint i1); temp _key (vint key); temp _value (vint value); gvar _m_entries p)
    SEP (data_at sh (tarray (tptr tentry) 32) entries p; fold_right sepcon emp (map (atomic_entry sh) entries);
         entry_hists entries h')).
  { Exists 0 i' h; entailer!. }
  eapply semax_loop.
  - Intros i i1 h'; forward.
    forward.
    rewrite sub_repr, and_repr; simpl.
    rewrite Zland_two_p with (n := 5) by omega.
    change (2 ^ 5) with 32.
    exploit (Z_mod_lt i1 32); [omega | intro Hi1].
    assert_PROP (Zlength entries = 32) as Hentries by entailer!.
    rewrite <- Hentries in Hi1 at 3.
    assert (isptr (Znth (i1 mod 32) entries Vundef)).
    { apply Forall_Znth; auto. }
    forward.
    forward.
    assert (Zlength h' = Zlength h) as Hlen.
    { 

assert (Zlength (sublist i (Zlength h) h) = Zlength (sublist i (Zlength h') h')) as Heq
        by (replace (sublist i (Zlength h) h) with (sublist i (Zlength h') h'); auto).
      rewrite !Zlength_sublist in Heq; try omega.
      destruct (Z_le_dec i (Zlength h')); [omega|].
      unfold sublist in Heq.
      rewrite Z2Nat_neg in Heq by omega.
      simpl in Heq; rewrite Zlength_nil in Heq; omega. }
    assert (i <= Zlength h') by omega.
    assert (map snd h' = map snd h) as Hsnd.
    { erewrite <- sublist_same with (al := h') by eauto.
      erewrite <- sublist_same with (al := h) by eauto.
      rewrite sublist_split with (al := h')(mid := i) by omega.
      rewrite sublist_split with (al := h)(mid := i) by omega.
      rewrite Hlen in *; rewrite !map_app; f_equal; [|congruence].
      eapply failed_CAS_fst; eauto. }
    rewrite extract_nth_sepcon with (i := i1 mod 32), Znth_map with (d' := Vundef); try rewrite Zlength_map;
      auto.
Print entry_hists.
    unfold entry_hists; erewrite extract_nth_sepcon with (i := i1)(l := map _ _), Znth_map, Znth_upto; simpl;
      auto; try omega.
    unfold atomic_entry; Intros lkey lval.
    rewrite atomic_loc_isptr.
    forward.
    forward.
    destruct (Znth i h' ([], [])) as (hki, hvi) eqn: Hhi.
    assert (Znth i h ([], []) = Znth i h' ([], []) /\
      sublist (i + 1) (Zlength h) h = sublist (i + 1) (Zlength h') h') as (Heq & Hi1).
    { match goal with H : sublist _ _ h = sublist _ _ h' |- _ =>
        erewrite sublist_next with (d := ([] : hist, [] : hist)),
                 sublist_next with (l0 := h')(d := ([] : hist, [] : hist)) in H by omega; inv H; auto end. }
    assert (ordered_hist hki).
    { match goal with H : wf_hists h l |- _ => destruct H as (Hwf & _) end.
      eapply Forall_Znth with (i0 := i) in Hwf; [|omega].
      rewrite Heq, Hhi in Hwf; tauto. }
    forward_call (Tsh, sh, field_address tentry [StructField _key] (Znth i entries Vundef), lkey, vint 0,
      hki, fun (h : hist) => !!(h = hki) && emp, k_R,
      fun (h : hist) (v : val) => !!(forall v0, last_value hki v0 -> v0 <> vint 0 -> v = v0) && emp).
    { entailer!.
      rewrite field_address_offset; simpl.
      rewrite isptr_offset_val_zero; auto.
      { rewrite field_compatible_cons; simpl.
        split; [unfold in_members; simpl|]; auto. } }
    { repeat (split; auto).
      intros ???????????? Ha.
      unfold k_R in *; simpl in *.
      eapply semax_pre, Ha.
      go_lowerx; entailer!.
      repeat split.
      + rewrite Forall_app; repeat constructor; auto.
        apply apply_int_ops in Hvx; auto.
      + intros ? Hin; rewrite in_app in Hin.
        destruct Hin as [? | [? | ?]]; subst; auto; contradiction.
      + intros ? [(? & ?) | (? & ? & Hin & ? & ?)] Hn; [contradiction Hn; auto|].
        specialize (Hhist _ _ Hin); apply nth_error_In in Hhist; subst; auto.
      + apply andp_right; auto.
        eapply derives_trans, precise_weak_precise, precise_andp2; auto. }
    Intros x; destruct x as (t, v); simpl in *.
    destruct v; try contradiction.
    focus_SEP 1.
    match goal with |- semax _ (PROP () (LOCALx ?Q (SEPx (_ :: ?R)))) _ _ =>
      forward_if (EX hki' : hist, PROP (hki' = hki ++ [(t, Load (vint key))] /\ i0 = Int.repr key \/
        exists r t', newer (hki ++ [(t, Load (Vint i0))]) t' /\
          hki' = hki ++ [(t, Load (vint 0)); (t', CAS (Vint r) (vint 0) (vint key))] /\
            (r = Int.zero \/ r = Int.repr key) /\
          forall v0 : val, last_value hki v0 -> v0 <> vint 0 -> Vint r = v0)
      (LOCALx Q (SEPx (ghost_hist hki' (field_address tentry [StructField _key] (Znth i entries Vundef)) :: R))))
    end.
    + match goal with |- semax _ (PROP () (LOCALx ?Q (SEPx ?R))) _ _ =>
        forward_if (PROP (i0 = Int.zero) (LOCALx Q (SEPx R))) end.
      { eapply semax_pre; [|apply semax_continue].
        unfold POSTCONDITION, abbreviate, overridePost.
        destruct (eq_dec EK_continue EK_normal); [discriminate|].
        unfold loop1_ret_assert.
        instantiate (1 := EX i : Z, EX h' : list (hist * hist),
          PROP (0 <= i < 20; Forall2 (failed_CAS key) (sublist 0 (i + 1) h) (sublist 0 (i + 1) h');
                sublist (i + 1) (Zlength h) h = sublist (i + 1) (Zlength h') h')
          LOCAL (temp _idx (vint i); temp _key (vint key); temp _value (vint value); gvar _m_entries p)
          SEP (data_at sh (tarray (tptr tentry) 20) entries p; fold_right_sepcon (map (atomic_entry sh) entries);
               entry_hists entries h')).
        Exists i (upd_Znth i h' (fst (Znth i h' ([], [])) ++ [(t, Load (Vint i0))], snd (Znth i h' ([], [])))).
        go_lower.
        apply andp_right.
        { assert (0 <= i < Zlength h') by (rewrite Hlen; omega).
          apply prop_right; repeat (split; auto).
          * erewrite sublist_split, sublist_len_1 with (i1 := i); try omega.
            erewrite sublist_split with (hi := i + 1), sublist_len_1 with (i1 := i)(d := ([] : hist, [] : hist));
              rewrite ?upd_Znth_Zlength; try omega.
            rewrite sublist_upd_Znth_l by omega.
            rewrite upd_Znth_same by omega.
            apply Forall2_app; auto.
            constructor; auto.
            unfold failed_CAS; simpl.
            rewrite Heq, Hhi; repeat eexists; eauto.
            match goal with H : forall v0, last_value hki v0 -> v0 <> vint 0 -> Vint i0 = v0 |- _ =>
              symmetry; apply H; auto end.
            rewrite ordered_last_value; auto.
          * rewrite upd_Znth_Zlength by omega.
            rewrite sublist_upd_Znth_r by omega; auto. }
        apply andp_right; [apply prop_right; auto|].
        fast_cancel.
        rewrite (sepcon_comm (ghost_hist _ _)).
        rewrite !sepcon_assoc, <- 4sepcon_assoc; apply sepcon_derives.
        * rewrite replace_nth_sepcon; apply sepcon_list_derives.
          { rewrite upd_Znth_Zlength; rewrite !Zlength_map; auto. }
          rewrite upd_Znth_Zlength; rewrite !Zlength_map; auto; intros.
          destruct (eq_dec i1 i).
          subst; rewrite upd_Znth_same by (rewrite Zlength_map; auto).
          rewrite Znth_map with (d' := Vundef) by auto.
          unfold atomic_entry.
          Exists lkey lval; entailer!.
          { rewrite upd_Znth_diff; rewrite ?Zlength_map; auto. }
        * rewrite (sepcon_comm _ (ghost_hist _ _)), <- sepcon_assoc, replace_nth_sepcon.
          assert (0 <= i < Zlength h') by omega.
          apply sepcon_list_derives.
          { rewrite upd_Znth_Zlength; rewrite !Zlength_map; auto. }
          rewrite upd_Znth_Zlength; rewrite !Zlength_map; auto; intros.
          destruct (eq_dec i1 i).
          subst; rewrite upd_Znth_same by (rewrite Zlength_map; auto).
          erewrite Znth_map, Znth_upto; simpl; auto; try omega.
          rewrite upd_Znth_same; auto; simpl.
          setoid_rewrite Hhi.
          rewrite sepcon_comm; auto.
          { rewrite upd_Znth_diff; auto.
            rewrite Zlength_upto in *.
            erewrite !Znth_map, !Znth_upto; auto; try omega.
            rewrite upd_Znth_diff; auto.
            setoid_rewrite Hlen; simpl in *; omega. } }
      { forward.
        entailer!. }
      Intros; subst.
      forward_call (Tsh, sh, field_address tentry [StructField _key] (Znth i entries Vundef), lkey, vint 0,
        vint key, vint 0, hki ++ [(t, Load (vint 0))],
        fun (h : hist) c v => !!(c = vint 0 /\ v = vint key /\ h = hki ++ [(t, Load (vint 0))]) && emp,
        k_R, fun (h : hist) (v : val) => !!(forall v0, last_value hki v0 -> v0 <> vint 0 -> v = v0) && emp).
      { entailer!.
        rewrite field_address_offset; simpl.
        rewrite isptr_offset_val_zero; auto.
        { rewrite field_compatible_cons; simpl.
          split; [unfold in_members; simpl|]; auto. } }
      { repeat (split; auto).
        intros ?????????????? Ha.
        unfold k_R in *; simpl in *.
        eapply semax_pre, Ha.
        go_lowerx; entailer!.
        repeat split.
        + rewrite Forall_app; repeat constructor; auto.
          apply apply_int_ops in Hvx; auto.
        + intros ? Hin; rewrite in_app in Hin.
          destruct Hin as [? | [? | ?]]; [| |contradiction].
          * intros.
            replace vx with (value_of e) by (symmetry; auto).
            if_tac; auto; absurd (value_of e = vint 0); auto.
          * subst; simpl; intros.
            if_tac; if_tac; auto; absurd (vx = vint 0); auto.
        + intros ? [(? & ?) | (? & ? & Hin & ? & ?)] Hn; [contradiction Hn; auto|].
          exploit Hhist.
          { rewrite in_app; eauto. }
          intro X; apply nth_error_In in X; subst; auto.
        + apply andp_right; auto.
          eapply derives_trans, precise_weak_precise, precise_andp2; auto. }
      Intros x; destruct x as (t', v); simpl in *.
      destruct v; try contradiction.
      match goal with |- semax _ (PROP () (LOCALx ?Q (SEPx ?R))) _ _ =>
        forward_if (PROP () (LOCALx (temp _t'3 (vint (if eq_dec i0 Int.zero then 0
          else if eq_dec i0 (Int.repr key) then 0 else 1)) :: Q) (SEPx R))) end.
      { forward.
        destruct (eq_dec i0 Int.zero); [absurd (i0 = Int.zero); auto|]; simpl force_val.
        destruct (Int.eq i0 (Int.repr key)) eqn: Hi0; [apply int_eq_e in Hi0 | apply int_eq_false_e in Hi0];
           simpl force_val.
        + destruct (eq_dec i0 (Int.repr key)); [apply drop_tc_environ | absurd (i0 = Int.repr key); auto].
        + destruct (eq_dec i0 (Int.repr key)); [absurd (i0 = Int.repr key); auto | apply drop_tc_environ]. }
      { forward.
        subst; rewrite eq_dec_refl; apply drop_tc_environ. }
      match goal with |- semax _ (PROP () (LOCALx ?Q (SEPx ?R))) _ _ =>
        forward_if (PROP (i0 = Int.zero \/ i0 = Int.repr key) (LOCALx Q (SEPx R))) end.
      { destruct (eq_dec i0 Int.zero); [absurd (Int.zero = Int.zero); auto|].
        destruct (eq_dec i0 (Int.repr key)); [absurd (Int.zero = Int.zero); auto|].
        eapply semax_pre; [|apply semax_continue].
        unfold POSTCONDITION, abbreviate, overridePost.
        destruct (eq_dec EK_continue EK_normal); [discriminate|].
        unfold loop1_ret_assert.
        go_lower.
        Exists i (upd_Znth i h' (fst (Znth i h' ([], [])) ++
          [(t, Load (vint 0)); (t', CAS (Vint i0) (vint 0) (vint key))], snd (Znth i h' ([], [])))).
        apply andp_right.
        { assert (0 <= i < Zlength h') by (rewrite Hlen; omega).
          apply prop_right; repeat (split; auto).
          * erewrite sublist_split, sublist_len_1 with (i1 := i); try omega.
            erewrite sublist_split with (hi := i + 1), sublist_len_1 with (i1 := i)(d := ([] : hist, [] : hist));
              rewrite ?upd_Znth_Zlength; try omega.
            rewrite sublist_upd_Znth_l by omega.
            rewrite upd_Znth_same by omega.
            apply Forall2_app; auto.
            constructor; auto.
            unfold failed_CAS; simpl.
            match goal with H : Forall _ (hki ++ _) |- _ => rewrite Forall_app in H; destruct H as (? & Ht);
              inv Ht end.
            simpl in *; rewrite Heq, Hhi; do 3 eexists; [|split; eauto]; repeat split; auto.
            match goal with H : forall v0, last_value hki v0 -> v0 <> vint 0 -> Vint i0 = v0 |- _ =>
              symmetry; apply H; auto end.
            rewrite ordered_last_value; auto.
          * rewrite upd_Znth_Zlength by omega.
            rewrite sublist_upd_Znth_r by omega; auto. }
        apply andp_right; [apply prop_right; auto|].
        fast_cancel.
        rewrite (sepcon_comm (ghost_hist _ _)).
        rewrite !sepcon_assoc, <- 4sepcon_assoc; apply sepcon_derives.
        * rewrite replace_nth_sepcon; apply sepcon_list_derives.
          { rewrite upd_Znth_Zlength; rewrite !Zlength_map; auto. }
          rewrite upd_Znth_Zlength; rewrite !Zlength_map; auto; intros.
          destruct (eq_dec i1 i).
          subst; rewrite upd_Znth_same by (rewrite Zlength_map; auto).
          rewrite Znth_map with (d' := Vundef) by auto.
          unfold atomic_entry.
          Exists lkey lval; entailer!.
          { rewrite upd_Znth_diff; rewrite ?Zlength_map; auto. }
        * rewrite (sepcon_comm _ (ghost_hist _ _)), <- sepcon_assoc, replace_nth_sepcon.
          assert (0 <= i < Zlength h') by omega.
          apply sepcon_list_derives.
          { rewrite upd_Znth_Zlength; rewrite !Zlength_map; auto. }
          rewrite upd_Znth_Zlength; rewrite !Zlength_map; auto; intros.
          destruct (eq_dec i1 i).
          subst; rewrite upd_Znth_same by (rewrite Zlength_map; auto).
          erewrite Znth_map, Znth_upto; simpl; auto; try omega.
          rewrite upd_Znth_same; auto; simpl.
          rewrite Hhi.
          rewrite <- app_assoc, sepcon_comm; auto.
          { rewrite upd_Znth_diff; auto.
            rewrite Zlength_upto in *.
            erewrite !Znth_map, !Znth_upto; auto; try omega.
            rewrite upd_Znth_diff; auto.
            rewrite Hlen; simpl in *; omega. } }
      { forward.
        entailer!.
        destruct (eq_dec i0 Int.zero); auto.
        destruct (eq_dec i0 (Int.repr key)); auto; discriminate. }
      intros.
      unfold exit_tycon, overridePost.
      destruct (eq_dec ek EK_normal); [subst | apply drop_tc_environ].
      Intros; unfold POSTCONDITION, abbreviate, normal_ret_assert, loop1_ret_assert, overridePost.
      rewrite eq_dec_refl.
      go_lower.
      apply andp_right; [apply prop_right; auto|].
      rewrite <- app_assoc; Exists (hki ++ [(t, Load (vint 0)); (t', CAS (Vint i0) (vint 0) (vint key))]);
        entailer!.
      right; do 3 eexists; eauto.
    + forward.
      Exists (hki ++ [(t, Load (Vint i0))]); entailer!.
    + rewrite (atomic_loc_isptr _ lval).
      Intros hki'.
      forward.
      forward.
      forward_call (Tsh, sh, field_address tentry [StructField _value] (Znth i entries Vundef), lval,
        vint value, vint 0, hvi, fun (h : hist) v => !!(v = vint value) && emp, v_R, fun (h : hist) => emp).
      { entailer!.
        rewrite field_address_offset; auto.
        { rewrite field_compatible_cons; simpl.
          split; [unfold in_members; simpl|]; auto. } }
      { repeat (split; auto).
        intros ????????????? Ha.
        unfold v_R in *; simpl in *.
        eapply semax_pre, Ha.
        go_lowerx; entailer!.
        apply andp_right; auto.
        eapply derives_trans, precise_weak_precise; auto. }
      Intros t'.
      forward.
      Exists i (upd_Znth i h' (hki', hvi ++ [(t', Store (vint value))])).
      apply andp_right; auto.
      apply andp_right.
      { apply prop_right; split; auto.
        split; [omega|].
        rewrite Heq, Hhi; simpl.
        split; [rewrite sublist_upd_Znth_l; auto; omega|].
        split.
        - rewrite upd_Znth_same by omega.
          match goal with H : _ \/ _ |- _ => destruct H as [(? & ?) | (? & ? & ? & ? & ? & ?)]; subst end.
          + do 4 eexists; eauto; split; eauto; split; eauto; split; auto.
            match goal with H : forall v0, last_value hki v0 -> v0 <> vint 0 -> vint key = v0 |- _ =>
              symmetry; apply H; auto end.
            rewrite ordered_last_value; auto.
          + do 4 eexists; eauto; split; eauto.
            split.
            * simpl; right; do 2 eexists; [|split; [eauto|]].
              { match goal with H : newer (_ ++ _) _ |- _ => unfold newer in H; rewrite Forall_app in H;
                  destruct H as (_ & Ht); inv Ht; auto end. }
              match goal with H : _ \/ _ |- _ => destruct H; subst; auto end.
            * split; auto.
              match goal with H : forall v0, last_value hki v0 -> v0 <> vint 0 -> Vint x = v0 |- _ =>
                symmetry; apply H; auto end.
              rewrite ordered_last_value; auto.
        - rewrite upd_Znth_Zlength by omega.
          rewrite sublist_upd_Znth_r; auto; omega. }
      apply andp_right; auto.
      fast_cancel.
      rewrite (sepcon_comm (ghost_hist _ _)).
      rewrite (sepcon_comm (ghost_hist _ _)).
      rewrite !sepcon_assoc, <- 4sepcon_assoc; apply sepcon_derives.
      * rewrite replace_nth_sepcon; apply sepcon_list_derives.
        { rewrite upd_Znth_Zlength; rewrite !Zlength_map; auto. }
        rewrite upd_Znth_Zlength; rewrite !Zlength_map; auto; intros.
        destruct (eq_dec i1 i).
        subst; rewrite upd_Znth_same by (rewrite Zlength_map; auto).
        rewrite Znth_map with (d' := Vundef) by auto.
        unfold atomic_entry.
        Exists lkey lval; entailer!.
        { rewrite upd_Znth_diff; rewrite ?Zlength_map; auto. }
      * rewrite sepcon_comm, replace_nth_sepcon.
        assert (0 <= i < Zlength h') by omega.
        apply sepcon_list_derives.
        { rewrite upd_Znth_Zlength; rewrite !Zlength_map; auto. }
        rewrite upd_Znth_Zlength; rewrite !Zlength_map; auto; intros.
        destruct (eq_dec i1 i).
        subst; rewrite upd_Znth_same by (rewrite Zlength_map; auto).
        erewrite Znth_map, Znth_upto; simpl; auto; try omega.
        rewrite upd_Znth_same; auto; simpl.
        { rewrite upd_Znth_diff; auto.
          rewrite Zlength_upto in *.
          erewrite !Znth_map, !Znth_upto; auto; try omega.
          rewrite upd_Znth_diff; auto.
          match goal with H : Zlength h' = _ |- _ => setoid_rewrite H; simpl in *; omega end. }
  - Intros i h'.
    forward.
    unfold loop2_ret_assert.
    Exists (i + 1) h'; entailer!.
    admit. (* list is long enough *)
Admitted.

Lemma failed_load_fst : forall v h h', Forall2 (failed_load v) h h' -> map snd h' = map snd h.
Proof.
  induction 1; auto.
  destruct H as (? & ? & ? & ? & ? & ? & ? & ?); simpl; f_equal; auto.
Qed.

Lemma body_get_item : semax_body Vprog Gprog f_get_item get_item_spec.
Proof.
  start_function.
  forward.
  eapply semax_pre with (P' := EX i : Z, EX h' : list (hist * hist),
    PROP (0 <= i < 20; Forall2 (failed_load key) (sublist 0 i h) (sublist 0 i h');
          sublist i (Zlength h) h = sublist i (Zlength h') h')
    LOCAL (temp _idx (vint i); temp _key (vint key); gvar _m_entries p)
    SEP (data_at sh (tarray (tptr tentry) 20) entries p; fold_right_sepcon (map (atomic_entry sh) entries);
         entry_hists entries h')).
  { Exists 0 h; rewrite sublist_nil; entailer!. }
  eapply semax_loop.
  - Intros i h'; forward.
    assert_PROP (Zlength entries = 20) by entailer!.
    assert (0 <= i < Zlength entries) by (replace (Zlength entries) with 20; auto).
    forward.
    { entailer!.
      apply isptr_is_pointer_or_null, Forall_Znth; auto. }
    rewrite extract_nth_sepcon with (i := i), Znth_map with (d' := Vundef); try rewrite Zlength_map; auto.
    unfold entry_hists; erewrite extract_nth_sepcon with (i := i)(l := map _ _), Znth_map, Znth_upto; simpl; auto;
      try omega.
    unfold atomic_entry; Intros lkey lval.
    rewrite atomic_loc_isptr.
    forward.
    forward.
    assert (Zlength h' = Zlength h) as Hlen.
    { assert (Zlength (sublist i (Zlength h) h) = Zlength (sublist i (Zlength h') h')) as Heq
        by (replace (sublist i (Zlength h) h) with (sublist i (Zlength h') h'); auto).
      rewrite !Zlength_sublist in Heq; try omega.
      destruct (Z_le_dec i (Zlength h')); [omega|].
      unfold sublist in Heq.
      rewrite Z2Nat_neg in Heq by omega.
      simpl in Heq; rewrite Zlength_nil in Heq; omega. }
    assert (i < Zlength h') by omega.
    assert (map snd h' = map snd h) as Hsnd.
    { erewrite <- sublist_same with (al := h') by eauto.
      erewrite <- sublist_same with (al := h) by eauto.
      rewrite sublist_split with (al := h')(mid := i) by omega.
      rewrite sublist_split with (al := h)(mid := i) by omega.
      rewrite Hlen in *; rewrite !map_app; f_equal; [|congruence].
      eapply failed_load_fst; eauto. }
    destruct (Znth i h' ([], [])) as (hki, hvi) eqn: Hhi.
    forward_call (Tsh, sh, field_address tentry [StructField _key] (Znth i entries Vundef), lkey, vint 0,
      hki, fun h => !!(h = hki) && emp, k_R,
      fun (h : hist) (v : val) => !!(forall v0, last_value hki v0 -> v0 <> vint 0 -> v = v0) && emp).
    { entailer!.
      rewrite field_address_offset; simpl.
      rewrite isptr_offset_val_zero; auto.
      { rewrite field_compatible_cons; simpl.
        split; [unfold in_members; simpl|]; auto. } }
    { repeat (split; auto).
      intros ???????????? Ha.
      unfold k_R in *; simpl in *.
      eapply semax_pre, Ha.
      go_lowerx; entailer!.
      repeat split.
      + rewrite Forall_app; repeat constructor; auto.
        apply apply_int_ops in Hvx; auto.
      + intros ? Hin; rewrite in_app in Hin.
        destruct Hin as [? | [? | ?]]; subst; auto; contradiction.
      + intros ? [(? & ?) | (? & ? & Hin & ? & ?)] Hn; [contradiction Hn; auto|].
        specialize (Hhist _ _ Hin); apply nth_error_In in Hhist; subst; auto.
      + apply andp_right; auto.
        eapply derives_trans, precise_weak_precise, precise_andp2; auto. }
    Intros x; destruct x as (t, v); simpl in *.
    destruct v; try contradiction.
    assert (Zlength h' = Zlength h).
    { assert (Zlength (sublist i (Zlength h) h) = Zlength (sublist i (Zlength h') h')) as Heq
        by (replace (sublist i (Zlength h) h) with (sublist i (Zlength h') h'); auto).
      rewrite !Zlength_sublist in Heq; omega. }
    assert (Znth i h ([], []) = Znth i h' ([], []) /\
      sublist (i + 1) (Zlength h) h = sublist (i + 1) (Zlength h') h') as (Heq & Hi1).
    { match goal with H : sublist _ _ h = sublist _ _ h' |- _ =>
        erewrite sublist_next with (d := ([] : hist, [] : hist)),
                 sublist_next with (l0 := h')(d := ([] : hist, [] : hist)) in H by omega; inv H; auto end. }
    assert (ordered_hist hki).
    { match goal with H : wf_hists h l |- _ => destruct H as (Hwf & _) end.
      eapply Forall_Znth with (i1 := i) in Hwf; [|omega].
      rewrite Heq, Hhi in Hwf; tauto. }
    match goal with |- semax _ (PROP () (LOCALx ?Q (SEPx ?R))) _ _ =>
      forward_if (PROP (i0 <> Int.repr key) (LOCALx Q (SEPx R))) end.
    + rewrite (atomic_loc_isptr _ lval).
      forward.
      forward.
      forward_call (Tsh, sh, field_address tentry [StructField _value] (Znth i entries Vundef), lval, vint 0,
        snd (Znth i h' ([], [])), fun (h : hist) => emp, v_R, fun (h : hist) (v : val) => emp).
      { entailer!.
        rewrite field_address_offset; auto.
        { rewrite field_compatible_cons; simpl.
          split; [unfold in_members; simpl|]; auto. } }
      { rewrite Hhi; fast_cancel. }
      { repeat (split; auto).
        intros ???????????? Ha.
        unfold v_R in *; simpl in *.
        eapply semax_pre, Ha.
        go_lowerx; entailer!.
        apply andp_right; auto.
        eapply derives_trans, precise_weak_precise; auto. }
      Intros x; destruct x as (t', v); simpl in *.
      forward.
      Exists (Int.signed v) i (upd_Znth i h' (fst (Znth i h' ([], [])) ++ [(t, Load (vint key))],
        snd (Znth i h' ([], [])) ++ [(t', Load (Vint v))])).
      apply andp_right.
      { apply prop_right.
        split; [apply Int.signed_range|].
        split; auto.
        split; [omega|].
        split; [|split].
        - rewrite sublist_upd_Znth_l; auto; omega.
        - rewrite upd_Znth_same by omega.
          rewrite Heq, Hhi in *; simpl in *.
          rewrite Int.repr_signed.
          do 3 eexists; eauto.
          split; eauto.
          split; eauto.
          match goal with H : forall v0, last_value hki v0 -> v0 <> vint 0 -> vint key = v0 |- _ =>
            symmetry; apply H; auto end.
          rewrite ordered_last_value; auto.
        - rewrite upd_Znth_Zlength by omega.
          rewrite sublist_upd_Znth_r by omega; auto. }
      apply andp_right; [apply prop_right; rewrite Int.repr_signed; auto|].
      fast_cancel.
      rewrite (sepcon_comm (ghost_hist _ _)).
      rewrite (sepcon_comm (ghost_hist _ _)).
      rewrite !sepcon_assoc, <- 4sepcon_assoc; apply sepcon_derives.
      * rewrite replace_nth_sepcon; apply sepcon_list_derives.
        { rewrite upd_Znth_Zlength; rewrite !Zlength_map; auto. }
        rewrite upd_Znth_Zlength; rewrite !Zlength_map; auto; intros.
        destruct (eq_dec i0 i).
        subst; rewrite upd_Znth_same by (rewrite Zlength_map; auto).
        rewrite Znth_map with (d' := Vundef) by auto.
        unfold atomic_entry.
        Exists lkey lval; entailer!.
        { rewrite upd_Znth_diff; rewrite ?Zlength_map; auto. }
      * rewrite sepcon_comm, replace_nth_sepcon.
        assert (0 <= i < Zlength h') by omega.
        rewrite Hhi; apply sepcon_list_derives.
        { rewrite upd_Znth_Zlength; rewrite !Zlength_map; auto. }
        rewrite upd_Znth_Zlength; rewrite !Zlength_map; auto; intros.
        destruct (eq_dec i0 i).
        subst; rewrite upd_Znth_same by (rewrite Zlength_map; auto).
        erewrite Znth_map, Znth_upto; simpl; auto; try omega.
        rewrite upd_Znth_same; auto; simpl.
        { rewrite upd_Znth_diff; auto.
          rewrite Zlength_upto in *.
          erewrite !Znth_map, !Znth_upto; auto; try omega.
          rewrite upd_Znth_diff; auto.
          simpl in *; omega. }
    + forward.
      entailer!.
    + Intros; match goal with |- semax _ (PROP () (LOCALx ?Q (SEPx ?R))) _ _ =>
        forward_if (PROP (i0 <> Int.zero) (LOCALx Q (SEPx R))) end.
      * forward.
        Exists 0 i (upd_Znth i h' (fst (Znth i h' ([], [])) ++ [(t, Load (vint 0))], snd (Znth i h' ([], [])))).
        apply andp_right.
        { apply prop_right.
          split; [split; computable|].
          split; auto.
          split; [omega|].
          split; [|split].
          * rewrite sublist_upd_Znth_l; auto; omega.
          * rewrite upd_Znth_same by omega.
            rewrite Heq, Hhi in *; simpl in *.
            do 3 eexists; eauto.
            split; eauto.
            split; eauto.
            match goal with H : forall v0, last_value hki v0 -> v0 <> vint 0 -> vint 0 = v0 |- _ =>
              symmetry; apply H; auto end.
            rewrite ordered_last_value; auto.
          * rewrite upd_Znth_Zlength by omega.
            rewrite sublist_upd_Znth_r; auto; omega. }
        apply andp_right; [apply prop_right; auto|].
        fast_cancel.
        rewrite (sepcon_comm (ghost_hist _ _)).
        rewrite (sepcon_comm (ghost_hist _ _)).
        rewrite !sepcon_assoc, <- 4sepcon_assoc; apply sepcon_derives.
        -- rewrite replace_nth_sepcon; apply sepcon_list_derives.
           { rewrite upd_Znth_Zlength; rewrite !Zlength_map; auto. }
           rewrite upd_Znth_Zlength; rewrite !Zlength_map; auto; intros.
           destruct (eq_dec i0 i).
           subst; rewrite upd_Znth_same by (rewrite Zlength_map; auto).
           rewrite Znth_map with (d' := Vundef) by auto.
           unfold atomic_entry.
           Exists lkey lval; entailer!.
           { rewrite upd_Znth_diff; rewrite ?Zlength_map; auto. }
        -- rewrite sepcon_comm, replace_nth_sepcon.
           assert (0 <= i < Zlength h') by omega.
           rewrite Hhi; apply sepcon_list_derives.
           { rewrite upd_Znth_Zlength; rewrite !Zlength_map; auto. }
           rewrite upd_Znth_Zlength; rewrite !Zlength_map; auto; intros.
           destruct (eq_dec i0 i).
           subst; rewrite upd_Znth_same by (rewrite Zlength_map; auto).
           erewrite Znth_map, Znth_upto; simpl; auto; try omega.
           rewrite upd_Znth_same; auto; simpl.
           rewrite sepcon_comm; auto.
           { rewrite upd_Znth_diff; auto.
             rewrite Zlength_upto in *.
             erewrite !Znth_map, !Znth_upto; auto; try omega.
             rewrite upd_Znth_diff; auto.
             simpl in *; omega. }
      * forward.
        entailer!.
      * intros.
        unfold exit_tycon, overridePost.
        destruct (eq_dec ek EK_normal); [subst | apply drop_tc_environ].
        Intros; unfold POSTCONDITION, abbreviate, normal_ret_assert, loop1_ret_assert.
        instantiate (1 := EX i : Z, EX h' : list (hist * hist),
          PROP (0 <= i < 20; Forall2 (failed_load key) (sublist 0 (i + 1) h) (sublist 0 (i + 1) h');
                sublist (i + 1) (Zlength h) h = sublist (i + 1) (Zlength h') h')
          LOCAL (temp _idx (vint i); temp _key (vint key); gvar _m_entries p)
          SEP (data_at sh (tarray (tptr tentry) 20) entries p; fold_right_sepcon (map (atomic_entry sh) entries);
               entry_hists entries h')).
        Exists i (upd_Znth i h' (fst (Znth i h' ([], [])) ++ [(t, Load (Vint i0))], snd (Znth i h' ([], [])))).
        go_lower.
        apply andp_right.
        { apply prop_right; repeat (split; auto).
          * erewrite sublist_split, sublist_len_1 with (i1 := i); try omega.
            erewrite sublist_split with (hi := i + 1), sublist_len_1 with (i1 := i)(d := ([] : hist, [] : hist));
              rewrite ?upd_Znth_Zlength; try omega.
            rewrite sublist_upd_Znth_l by omega.
            rewrite upd_Znth_same by omega.
            apply Forall2_app; auto.
            constructor; auto.
            unfold failed_load; simpl.
            rewrite Heq, Hhi; repeat eexists; eauto.
            match goal with H : forall v0, last_value hki v0 -> v0 <> vint 0 -> Vint i0 = v0 |- _ =>
              symmetry; apply H; auto end.
            rewrite ordered_last_value; auto.
          * rewrite upd_Znth_Zlength by omega.
            rewrite sublist_upd_Znth_r by omega; auto. }
        apply andp_right; [apply prop_right; auto|].
        fast_cancel.
        rewrite (sepcon_comm (ghost_hist _ _)).
        rewrite !sepcon_assoc, <- 4sepcon_assoc; apply sepcon_derives.
        -- rewrite replace_nth_sepcon; apply sepcon_list_derives.
           { rewrite upd_Znth_Zlength; rewrite !Zlength_map; auto. }
          rewrite upd_Znth_Zlength; rewrite !Zlength_map; auto; intros.
          destruct (eq_dec i1 i).
          subst; rewrite upd_Znth_same by (rewrite Zlength_map; auto).
           rewrite Znth_map with (d' := Vundef) by auto.
          unfold atomic_entry.
          Exists lkey lval; entailer!.
          { rewrite upd_Znth_diff; rewrite ?Zlength_map; auto. }
        -- rewrite (sepcon_comm _ (ghost_hist _ _)), <- sepcon_assoc, replace_nth_sepcon.
           assert (0 <= i < Zlength h') by omega.
           rewrite Hhi; apply sepcon_list_derives.
           { rewrite upd_Znth_Zlength; rewrite !Zlength_map; auto. }
           rewrite upd_Znth_Zlength; rewrite !Zlength_map; auto; intros.
           destruct (eq_dec i1 i).
           subst; rewrite upd_Znth_same by (rewrite Zlength_map; auto).
           erewrite Znth_map, Znth_upto; simpl; auto; try omega.
           rewrite upd_Znth_same; auto; simpl.
           rewrite sepcon_comm; auto.
           { rewrite upd_Znth_diff; auto.
             rewrite Zlength_upto in *.
             erewrite !Znth_map, !Znth_upto; auto; try omega.
             rewrite upd_Znth_diff; auto.
             match goal with H : Zlength h' = _ |- _ => setoid_rewrite H; simpl in *; omega end. }
  - Intros i h'.
    forward.
    unfold loop2_ret_assert.
    Exists (i + 1) h'; entailer!.
    admit. (* list is long enough *)
Admitted.
