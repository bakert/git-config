# Crazed level of git efficiency. Probably bananas.

# Pretty git log via https://registerspill.thorstenball.com/p/how-i-use-git
# Although I updated it to not have a hardcoded number of commits.
HASH="%C(always,yellow)%h%C(always,reset)"
RELATIVE_TIME="%C(always,green)%ar%C(always,reset)"
AUTHOR="%C(always,bold blue)%an%C(always,reset)"
REFS="%C(always,red)%d%C(always,reset)"
SUBJECT="%s"

FORMAT="$HASH $RELATIVE_TIME{$AUTHOR{$REFS $SUBJECT"

# Determine defaultBranch once per repo, store it if not set
get_default_branch() {
  local branch
  branch=$(git config --get bakert.defaultBranch 2>/dev/null)

  if [[ -z "$branch" ]]; then
    branch=$(git remote show origin 2>/dev/null | awk '/HEAD branch/ {print $NF}')
    branch=${branch:-master}

    git config --local bakert.defaultBranch "$branch"
    echo "Set bakert.defaultBranch to '$branch' in local git config" >&2
  fi

  echo "$branch"
}

# Delete a branch, skipping if it's checked out in a worktree
safe_delete_branch() {
  local branch=$1
  local worktree_path=$(git worktree list --porcelain | awk -v branch="$branch" '
    /^worktree / { path=$2 }
    /^branch / && $2 == "refs/heads/" branch { print path; exit }
  ')

  if [[ -n "$worktree_path" ]]; then
    echo "Skipping branch '$branch' (checked out in worktree at $worktree_path)" >&2
    echo "  → Use Conductor to archive this workspace" >&2
    return 0
  fi

  git branch -D "$branch"
}

# Get the main worktree directory (first worktree in list)
get_main_worktree() {
  git worktree list --porcelain | awk '/^worktree / { print $2; exit }'
}

# Check if we're in a secondary worktree (not main)
in_secondary_worktree() {
  local current=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  local main=$(get_main_worktree)
  [[ -n "$current" ]] && [[ -n "$main" ]] && [[ "$current" != "$main" ]]
}

# Perform an operation that might fail if the current branch is implicated in a way that won't fail
# Leaves you on default branch after if your current branch ceased to exist.
# Works with multi-worktree setup by using detached HEAD at origin/default
with_default_branch() {
  local current_branch=$(git rev-parse --abbrev-ref HEAD)
  local default_branch=$(get_default_branch)

  if [[ "$current_branch" != "$default_branch" ]]; then
    # Use detached HEAD to avoid conflicts with other worktrees
    git switch --detach "origin/$default_branch"
  fi

  "$@"

  if [[ "$current_branch" != "$default_branch" ]] && git show-ref --verify --quiet "refs/heads/$current_branch"; then
    # Original branch still exists, switch back to it
    git switch "$current_branch"
  elif [[ "$current_branch" != "$default_branch" ]]; then
    # Original branch was deleted, switch to local default
    git switch "$default_branch"
  fi
}

## Functions not aliases to allow completions
ga()    { git add "$@"; }; compdef _git ga=git-add
gaa()   { git add . "$@"; }; compdef _git gaa=git-add
# Equivlent to `git add !$`
gal() {
  emulate -L zsh
  setopt noglob

  local cmd last
  cmd=$(fc -ln -1) || return 1
  local -a words
  words=(${(z)cmd})
  (( ${#words} )) || { echo "No history."; return 1; }

  last=${words[-1]}
  last=${(Q)last}       # remove surrounding quotes if any

  # Expand ~ / ~user without enabling globbing
  if [[ $last == "~"* ]]; then
    last=${~last}
  fi

  [[ -n $last ]] || { echo "No last arg."; return 1; }
  git add -- "$last"
}; compdef _git gal=git-add
gap()    { git add -p "$@"; }; compdef _git gap=git-add
gb()     { git branch "$@"; }; compdef _git gb=git-branch
gbd()    { with_default_branch git branch -D "$@"; }; compdef _git gbd=git-branch
gbdc()   {
  local current_branch=$(git rev-parse --abbrev-ref HEAD)
  local default_branch=$(get_default_branch)

  if [[ "$current_branch" != "$default_branch" ]]; then
    git switch "$default_branch"
    git branch -D "$current_branch"
  else
    echo "Cannot delete the default branch"
    return 1
  fi
}; compdef _git gbdc=git-branch
gbl()    { git blame "$@"; }; compdef _git gbl=git-blame
gc()     { git commit "$@"; }; compdef _git gc=git-commit
gca()    { git commit --amend "$@"; }; compdef _git gca=git-commit
gcae()   { git commit --amend --no-edit "$@"; }; compdef _git gcae=git-commit
gcan()   { git commit --amend -n "$@"; }; compdef _git gcan=git-commit
gcane()  { git commit --amend -n --no-edit "$@"; }; compdef _git gcane=git-commit
gcco()   { git commit -C ORIG_HEAD; }; compdef _git gcco=git-commit
gded()   { gpru && gemp }; compdef _git gclb=git-branch
gclear() { grra && gclfd }; compdef _git gclear=git-reset
gclfd()  { git clean -fd "$@" }; compdef _git gclfd=git-clean
gcm()    { git commit -m "$@"; }; compdef _git gcm=git-commit
gcn()    { git commit -n "$@"; }; compdef _git gcn=git-commit
gco()    { git checkout "$@"; }; compdef _git gco=git-checkout
gcp()    { git cherry-pick "$@" }; compdef _git gcp=git-cherry-pick
gcpa()   { git cherry-pick --abort "$@" }; compdef _git gcpa=git-cherry-pick
gcpc()   { git cherry-pick --continue "$@" }; compdef _git gcpc=git-cherry-pick
glc()    { git clone "$@"; }; compdef _git glc=git-clone
gd()     { git diff "$@"; }; compdef _git gd=git-diff
gdc()    { git diff --cached "$@"; }; compdef _git gdc=git-diff
gdd()    { gfo && git diff "origin/$(get_default_branch)" "$@"; }; compdef _git gdd=git-diff
# Delete all local branches that don't have changes not already in default branch
gemp() {
  gfo
  local cleanup_empty_branches() {
    local default_branch=$(get_default_branch)
    for branch in $(git for-each-ref --format='%(refname:short)' refs/heads/); do
      if [[ "$branch" != "$default_branch" ]]; then
        local count=$(git rev-list --count "$branch" --not "origin/$default_branch")
        if [[ "$count" -eq 0 ]]; then
          echo "Deleting branch: $branch"
          safe_delete_branch "$branch"
        fi
      fi
    done
  }
  with_default_branch cleanup_empty_branches
}
# Fetch and optionally update local default branch
# Works with multi-worktree setup - doesn't fail if default is checked out elsewhere
fetch_default_branch() {
  local default_branch=$(get_default_branch)
  local current_branch=$(git rev-parse --abbrev-ref HEAD)

  # If we're on the default branch, pull to update it
  if [[ "$current_branch" == "$default_branch" ]]; then
    git pull origin "$default_branch"
  else
    # Otherwise, fetch the remote and try to update local branch
    git fetch origin "$default_branch"

    # Try to update the local branch, but don't fail if it's checked out elsewhere
    if git fetch origin "$default_branch:$default_branch" 2>/dev/null; then
      echo "Updated local $default_branch" >&2
    else
      echo "Note: local $default_branch not updated (may be checked out in another worktree)" >&2
    fi
  fi
}

gfo() {
  fetch_default_branch
}; compdef _git gfo=git-fetch
# Make a gist, guessing exactly what you want a gist of based on state of repo
gg() {
local target=$1
  local desc=""
  local filename=""
  local url=""

  if [[ -z $target ]]; then
    if [[ -n $(git status --porcelain) ]]; then
      desc="Working copy diff"
      filename="working.diff"
      url=$((git diff HEAD && git ls-files --others --exclude-standard | xargs -I {} git diff /dev/null {}) | gh gist create -f "$filename" -d "$desc" - | tail -n1)
    else
      desc="Top commit diff (HEAD)"
      filename="head.diff"
      url=$(git show HEAD | gh gist create -f "$filename" -d "$desc" - | tail -n1)
    fi
  elif [[ $target == "$(get_default_branch)" ]]; then
    gfo
    local default_branch=$(get_default_branch)
    desc="Diff from $default_branch"
    filename="$default_branch.diff"
    url=$(git diff "origin/$default_branch...HEAD" | gh gist create -f "$filename" -d "$desc" - | tail -n1)
  else
	desc="Diff of $target"
	filename="$target.diff"
	url=$(git diff "$target...HEAD" | gh gist create -f "$filename" -d "$desc" - | tail -n1)
  fi

  echo "$url"
  open "$url"
}; compdef _git gg=git-show
# Make a gist of the difference between working copy and default branch
ggd()    { gfo && gg "$(get_default_branch)"; }; compdef _git ggd=git-show
gkilla() { git reset --hard && git clean -fd "$@"; }; compdef _git gpurge=git-clean
gkill()  { git restore . && git clean -fd "$@"; }; compdef _git gclean=git-clean
gl()     { git log "$@"; }; compdef _git gl=git-log
glp()    { git log -p "$@"; }; compdef _git glp=git-log
# Pretty one-liner log
glpr() {
  local git_args=()
  if [[ $1 =~ ^-[0-9]+$ ]] || [[ $1 =~ ^--max-count=[0-9]+$ ]] || [[ $1 =~ ^-n$ && $2 =~ ^[0-9]+$ ]]; then
    git_args=("$@")
  else
    git_args=("$@")
  fi
  git log --pretty="tformat:$FORMAT" "${git_args[@]}" |
  column -t -s '{' |
  less -XRS --quit-if-one-screen
}; compdef _git glpr=git-log
gm()   { git mv "$@"; }; compdef _git gm=git-mv
gp()   { git pull "$@"; }; compdef _git gp=git-pull
gpf()  { git push --force-with-lease "$@"; }; compdef _git gpf=git-push
gpr()  { gh pr create "$@"; }; compdef _gh gpr=git-switch
gprb()  { gh pr create -B "$@"; }; compdef _git gprb=git-switch
gprd()  { gh pr create -d "$@"; }; compdef _gh gprd=git-switch
gprdb() { gh pr create -d -B "$@"; }; compdef _git gprdb=git-switch
# Remove local branches that aren't on remote any more
gpru() {
  cleanup_gone_branches() {
    git remote update origin --prune
    gone_branches=()
    while IFS= read -r br; do
      gone_branches+=("$br")
    done < <(git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads | awk '$2=="[gone]" {print $1}')
    if [ ${#gone_branches[@]} -gt 0 ]; then
      for branch in "${gone_branches[@]}"; do
        safe_delete_branch "$branch"
      done
    fi
  }
  with_default_branch cleanup_gone_branches
}
gpso()  { git push --set-upstream origin "${@:-$(git branch --show-current)}"; }; compdef _git gpso=git-push
grb()   { git rebase --update-refs "$@"; }; compdef _git grb=git-rebase
grba()  { git rebase --abort "$@"; }; compdef _git grba=git-rebase
grbc()  { git rebase --continue "$@"; }; compdef _git grbc=git-rebase
grbd()  { gfo && git rebase --update-refs "origin/$(get_default_branch)" "$@"; }; compdef _git grbd=git-rebase
grbi()  { gfo && git rebase --update-refs -i "origin/$(get_default_branch)" "$@"; }; compdef _git grbi=git-rebase
grl()   { git reflog "$@"; }; compdef _git grl=git-reflog
grra()  { grsa && grta; }; compdef _git grra=git-reset
grs()   { git reset "$@"; }; compdef _git grs=git-reset
grsa()  { git reset . "$@"; }; compdef _git grs=git-reset
grsh1() { git reset HEAD~1 "$@"; }; compdef _git grsh1=git-reset
grsh2() { git reset HEAD~2 "$@"; }; compdef _git grsh2=git-reset
grsh3() { git reset HEAD~3 "$@"; }; compdef _git grsh3=git-reset
grsh4() { git reset HEAD~4 "$@"; }; compdef _git grsh4=git-reset
grsh5() { git reset HEAD~5 "$@"; }; compdef _git grsh5=git-reset
grsh6() { git reset HEAD~6 "$@"; }; compdef _git grsh6=git-reset
grsh7() { git reset HEAD~7 "$@"; }; compdef _git grsh7=git-reset
grsh8() { git reset HEAD~8 "$@"; }; compdef _git grsh8=git-reset
grsh9() { git reset HEAD~9 "$@"; }; compdef _git grsh9=git-reset
grt()   { git restore "$@"; }; compdef _git grt=git-restore
grta()  { git restore . "$@"; }; compdef _git grta=git-restore
grts()  { git restore --staged "$@"; }; compdef _git grts=git-restore
grtsa() { git restore --staged . "$@"; }; compdef _git grtsa=git-restore
grm()   { git rm "$@"; }; compdef _git grm=git-rm
gs()    { git status "$@"; }; compdef _git gs=git-status
gsh()   { git show "$@"; }; compdef _git gsh=git-show
gshn()  { git show --name-only "$@"; }; compdef _git gsh=git-show
gst()   { git stash "$@"; }; compdef _git gst=git-stash
gstd()  { git stash drop "$@"; }; compdef _git gstd=git-stash
gstl()  { git stash list "$@"; }; compdef _git gstl=git-stash
gstp()  { git stash pop "$@"; }; compdef _git gstp=git-stash
gstsp() { git stash show -p "$@"; }; compdef _git gsts=git-stash
gstu()  { git stash -u "$@"; }; compdef _git gstu=git-stash
gsw() {
  local branch=$1

  # If we're in a Conductor worktree, cd to main first
  if in_secondary_worktree; then
    local main_worktree=$(get_main_worktree)
    echo "→ ${main_worktree:t}"
    cd "$main_worktree"
  fi

  # If no arguments or starts with -, pass through to git switch
  if [[ -z "$branch" ]] || [[ "$branch" == -* ]]; then
    git switch "$@"
    return $?
  fi

  # Check if branch exists locally
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    # Check if it's checked out in a worktree
    local worktree_path=$(git worktree list --porcelain | awk -v branch="$branch" '
      /^worktree / { path=$2 }
      /^branch / && $2 == "refs/heads/" branch { print path; exit }
    ')

    local current_worktree=$(git rev-parse --show-toplevel)

    if [[ -n "$worktree_path" ]] && [[ "$worktree_path" != "$current_worktree" ]]; then
      # Branch is checked out in a different worktree, cd there
      echo "→ ${worktree_path:t}"
      cd "$worktree_path"
    else
      # Branch exists locally and either not checked out or in current worktree
      git switch "$branch"
    fi
  else
    # Branch doesn't exist locally, pass through to git switch
    git switch "$@"
  fi
}; compdef _git gsw=git-switch
gswc()  {
  # If we're in a Conductor worktree, cd to main first
  if in_secondary_worktree; then
    local main_worktree=$(get_main_worktree)
    echo "→ ${main_worktree:t}"
    cd "$main_worktree"
  fi
  git switch -c "$@"
}; compdef _git gswc=git-switch
gswcd() {
  # If we're in a Conductor worktree, cd to main first
  if in_secondary_worktree; then
    local main_worktree=$(get_main_worktree)
    echo "→ ${main_worktree:t}"
    cd "$main_worktree"
  fi
  gfo && git switch -c "$1" "origin/$(get_default_branch)"
}; compdef _git gswcd=git-switch
gswd()  { gsw $(get_default_branch); }; compdef _git gswd=git-switch
gswp()  { git switch - "$@"; }; compdef _git gswp=git-switch
gtc()   { gt create "$@"; }
gtl()   { gt log "$@"; }
gtm()   { gt move "$@"; }
gtr()   { gt restack "$@"; }
gts()   { gt submit "$@"; }
gtsy()  { gt sync "$@"; }
gtt()   { gt track "$@"; }
gup()   { gfo && gpru && gemp }; compdef _git gup=git-branch
gwl()   { git worktree list "$@"; }; compdef _git gwl=git-worktree
gwlb()  { git worktree list "$@" | grep -v "detached HEAD"; }; compdef _git gwlb=git-worktree
gwip() {
  current_branch=$(git branch --show-current)
  default_branch=$(get_default_branch)

  if [[ "$current_branch" == "$default_branch" ]]; then
    wip_branch="wip-$(date +%Y-%m-%d-%H-%M)"
    echo "Cannot commit WIP on $default_branch. Creating branch: $wip_branch"
    git switch -c "$wip_branch"
  fi

  git add . && git commit -m "WIP" -n
}

