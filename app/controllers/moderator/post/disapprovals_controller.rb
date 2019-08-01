module Moderator
  module Post
    class DisapprovalsController < ApplicationController
      before_action :approver_only
      skip_before_action :api_check
      respond_to :js, :json, :xml

      def create
        cookies.permanent[:moderated] = Time.now.to_i
        pd_params = post_disapproval_params
        @post_disapproval = PostDisapproval.create_with(post_disapproval_params).find_or_create_by(user_id: CurrentUser.id, post_id: pd_params[:post_id])
        @post_disapproval.reason = pd_params[:reason]
        @post_disapproval.message = pd_params[:message]
        @post_disapproval.save
        respond_with(@post_disapproval)
      end

      def index
        @post_disapprovals = PostDisapproval.paginate(params[:page])
      end

      private

      def post_disapproval_params
        params.require(:post_disapproval).permit(%i[post_id reason message])
      end
    end
  end
end
