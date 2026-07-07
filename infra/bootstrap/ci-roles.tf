locals {
  gha_aud    = "token.actions.githubusercontent.com:aud"
  gha_sub    = "token.actions.githubusercontent.com:sub"
  account_id = data.aws_caller_identity.current.account_id
}

# ---------------------------------------------------------------------------
# Role 1: ci-readonly-plan — assumable from ANY ref of this repo (incl. PRs).
# Read-only: enough for `terraform plan`, never enough to change anything.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ci_plan_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = local.gha_aud
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = local.gha_sub
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "ci_readonly_plan" {
  name                 = "${var.project}-ci-readonly-plan"
  description          = "GitHub Actions: read-only role for terraform plan on pull requests"
  assume_role_policy   = data.aws_iam_policy_document.ci_plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "ci_plan_readonly" {
  role       = aws_iam_role.ci_readonly_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# `terraform plan` must take and release the S3-native state lock (*.tflock);
# scoping PutObject/DeleteObject to the lock suffix keeps the state itself read-only.
resource "aws_iam_role_policy" "ci_plan_state_lock" {
  name = "tfstate-lockfile"
  role = aws_iam_role.ci_readonly_plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StateLockfile"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.tfstate.arn}/*.tflock"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Role 2: ci-deploy — assumable ONLY from main, release tags, or a gated
# GitHub environment. PowerUserAccess excludes IAM; the inline policy grants
# just enough IAM to manage project-prefixed roles/policies, and explicitly
# denies touching the CI roles themselves (no self-privilege-escalation).
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ci_deploy_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = local.gha_aud
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = local.gha_sub
      values = [
        "repo:${var.github_repo}:ref:refs/heads/main",
        "repo:${var.github_repo}:ref:refs/tags/v*",
        "repo:${var.github_repo}:environment:*",
      ]
    }
  }
}

resource "aws_iam_role" "ci_deploy" {
  name                 = "${var.project}-ci-deploy"
  description          = "GitHub Actions: deploy role for main, release tags, and gated environments"
  assume_role_policy   = data.aws_iam_policy_document.ci_deploy_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "ci_deploy_poweruser" {
  role       = aws_iam_role.ci_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy" "ci_deploy_iam_scoped" {
  name = "iam-scoped-to-project"
  role = aws_iam_role.ci_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadIam"
        Effect   = "Allow"
        Action   = ["iam:Get*", "iam:List*"]
        Resource = "*"
      },
      {
        Sid    = "ManageProjectRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:UpdateRole",
          "iam:UpdateRoleDescription",
          "iam:UpdateAssumeRolePolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
        ]
        Resource = "arn:aws:iam::${local.account_id}:role/${var.project}-*"
      },
      {
        Sid      = "PassProjectRoles"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "arn:aws:iam::${local.account_id}:role/${var.project}-*"
      },
      {
        Sid    = "ManageProjectPolicies"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:TagPolicy",
          "iam:UntagPolicy",
        ]
        Resource = "arn:aws:iam::${local.account_id}:policy/${var.project}-*"
      },
      {
        Sid      = "ServiceLinkedRoles"
        Effect   = "Allow"
        Action   = "iam:CreateServiceLinkedRole"
        Resource = "*"
      },
      {
        Sid      = "ProtectCiRoles"
        Effect   = "Deny"
        Action   = "iam:*"
        Resource = "arn:aws:iam::${local.account_id}:role/${var.project}-ci-*"
      }
    ]
  })
}
